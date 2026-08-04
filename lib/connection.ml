type limits = {max_header_size: int; max_body_size: int}

let default_limits =
  {max_header_size= 64 * 1024; max_body_size= 10 * 1024 * 1024}

module type IO = sig
  type t

  val read : t -> bytes -> off:int -> len:int -> int

  val write : t -> string -> off:int -> len:int -> unit
end

module Make (Io : IO) = struct
  type input = {io: Io.t; mutable buffered: string}

  exception Clean_eof

  exception Protocol_error of Http.parse_error

  let find_substring haystack needle =
    let haystack_length = String.length haystack in
    let needle_length = String.length needle in
    let rec search index =
      if index + needle_length > haystack_length then None
      else
        let rec matches offset =
          offset = needle_length
          || haystack.[index + offset] = needle.[offset]
             && matches (offset + 1)
        in
        if matches 0 then Some index else search (index + 1)
    in
    search 0

  let read_more input =
    let bytes = Bytes.create 4096 in
    let count = Io.read input.io bytes ~off:0 ~len:(Bytes.length bytes) in
    if count = 0 then
      if String.length input.buffered = 0 then raise Clean_eof
      else raise (Protocol_error (`Bad_request "unexpected end of request")) ;
    input.buffered <- input.buffered ^ Bytes.sub_string bytes 0 count

  let take_until ?(too_large = `Headers_too_large) input ~marker ~limit =
    let rec loop () =
      match find_substring input.buffered marker with
      | Some index ->
          if index > limit then raise (Protocol_error too_large) ;
          let value = String.sub input.buffered 0 index in
          let consumed = index + String.length marker in
          input.buffered <-
            String.sub input.buffered consumed
              (String.length input.buffered - consumed) ;
          value
      | None ->
          if String.length input.buffered > limit then
            raise (Protocol_error too_large) ;
          read_more input ;
          loop ()
    in
    loop ()

  let take_exact input length =
    let result = Bytes.create length in
    let copied = min length (String.length input.buffered) in
    Bytes.blit_string input.buffered 0 result 0 copied ;
    input.buffered <-
      String.sub input.buffered copied (String.length input.buffered - copied) ;
    let rec fill offset =
      if offset < length then (
        let count =
          Io.read input.io result ~off:offset ~len:(length - offset)
        in
        if count = 0 then
          raise
            (Protocol_error (`Bad_request "unexpected end of request body")) ;
        fill (offset + count) )
    in
    fill copied ;
    Bytes.unsafe_to_string result

  let parse_hex value =
    let digits =
      match String.index_opt value ';' with
      | None -> value
      | Some index -> String.sub value 0 index
    in
    let digits = String.trim digits in
    if digits = "" || String.length digits > 16 then None
    else
      try
        let parsed = Int64.of_string ("0x" ^ digits) in
        if parsed < 0L || parsed > Int64.of_int max_int then None
        else Some (Int64.to_int parsed)
      with Failure _ -> None

  let read_chunked input limits =
    let body = Buffer.create 4096 in
    let rec chunks total =
      let line =
        take_until ~too_large:(`Bad_request "chunk-size line too long") input
          ~marker:"\r\n" ~limit:1024
      in
      match parse_hex line with
      | None -> raise (Protocol_error (`Bad_request "invalid chunk size"))
      | Some 0 -> trailers ()
      | Some size ->
          if size > limits.max_body_size - total then
            raise (Protocol_error `Body_too_large) ;
          Buffer.add_string body (take_exact input size) ;
          if not (String.equal (take_exact input 2) "\r\n") then
            raise (Protocol_error (`Bad_request "invalid chunk terminator")) ;
          chunks (total + size)
    and trailers () =
      let rec loop consumed =
        let line =
          take_until input ~marker:"\r\n"
            ~limit:(limits.max_header_size - consumed)
        in
        if line = "" then ()
        else if not (String.contains line ':') then
          raise (Protocol_error (`Bad_request "invalid trailer field"))
        else loop (consumed + String.length line + 2)
      in
      loop 0
    in
    chunks 0 ; Buffer.contents body

  let write_string io string =
    Io.write io string ~off:0 ~len:(String.length string)

  let read_request input limits =
    let head =
      try take_until input ~marker:"\r\n\r\n" ~limit:limits.max_header_size
      with Protocol_error `Headers_too_large ->
        raise (Protocol_error `Headers_too_large)
    in
    match
      Http.parse_request_head ~max_body_size:limits.max_body_size
        (head ^ "\r\n\r\n")
    with
    | Error error -> raise (Protocol_error error)
    | Ok (request, framing) ->
        let expects = Headers.tokens "expect" request.headers in
        if expects <> [] && expects <> ["100-continue"] then
          raise (Protocol_error `Expectation_failed) ;
        ( match (expects, framing) with
        | ["100-continue"], Http.Fixed length when length > 0 ->
            write_string input.io "HTTP/1.1 100 Continue\r\n\r\n"
        | ["100-continue"], Http.Chunked ->
            write_string input.io "HTTP/1.1 100 Continue\r\n\r\n"
        | _ -> () ) ;
        let body =
          match framing with
          | Http.Empty -> ""
          | Http.Fixed length -> take_exact input length
          | Http.Chunked -> read_chunked input limits
        in
        Request.with_body request body

  let request_wants_close (request : Request.t) =
    let tokens = Headers.tokens "connection" request.headers in
    match request.version with
    | `HTTP_1_1 -> List.mem "close" tokens
    | `HTTP_1_0 -> not (List.mem "keep-alive" tokens)

  let error_response = function
    | `Body_too_large -> Response.text ~status:413 "Request body too large\n"
    | `Expectation_failed -> Response.text ~status:417 "Expectation failed\n"
    | `Headers_too_large ->
        Response.text ~status:431 "Request headers too large\n"
    | `Unsupported_transfer_encoding ->
        Response.text ~status:501 "Transfer encoding not supported\n"
    | `Bad_request message -> Response.text ~status:400 (message ^ "\n")

  let websocket_handshake (request : Request.t) =
    let bad_request message =
      Error (Response.text ~status:400 (message ^ "\n"))
    in
    if not (String.equal request.meth "GET") then
      bad_request "WebSocket upgrade requires GET"
    else if request.version <> `HTTP_1_1 then
      bad_request "WebSocket upgrade requires HTTP/1.1"
    else if
      not (List.mem "websocket" (Headers.tokens "upgrade" request.headers))
    then bad_request "missing WebSocket Upgrade header"
    else if
      not (List.mem "upgrade" (Headers.tokens "connection" request.headers))
    then bad_request "missing WebSocket Connection header"
    else
      match Headers.get_all "sec-websocket-version" request.headers with
      | ["13"] -> (
        match Headers.get_all "sec-websocket-key" request.headers with
        | [key] -> (
          match Websocket.For_connection.accept_key key with
          | Some accept -> Ok accept
          | None -> bad_request "invalid Sec-WebSocket-Key" )
        | _ -> bad_request "WebSocket upgrade requires one Sec-WebSocket-Key"
        )
      | _ ->
          Error
            (Response.empty
               ~headers:(Headers.of_list [("sec-websocket-version", "13")])
               426 )

  let serve_websocket input request response upgrade =
    match websocket_handshake request with
    | Error error ->
        write_string input.io
          (Http.serialize_response ~request_method:request.meth ~close:true
             error )
    | Ok accept -> (
        write_string input.io
          (Http.serialize_websocket_upgrade ~accept
             ~headers:(Response.headers response) ) ;
        let read bytes ~off ~len =
          if String.length input.buffered = 0 then
            Io.read input.io bytes ~off ~len
          else
            let count = min len (String.length input.buffered) in
            Bytes.blit_string input.buffered 0 bytes off count ;
            input.buffered <-
              String.sub input.buffered count
                (String.length input.buffered - count) ;
            count
        in
        let write string ~off ~len = Io.write input.io string ~off ~len in
        let websocket =
          Websocket.For_connection.create
            ~max_message_size:upgrade.Response.max_message_size ~read ~write
        in
        try
          upgrade.handler websocket ;
          if Websocket.is_open websocket then Websocket.close websocket
        with _ -> (
          if Websocket.is_open websocket then
            try Websocket.close ~code:1011 websocket with _ -> () ) )

  let serve ?(limits = default_limits) io handler =
    if limits.max_header_size <= 0 || limits.max_body_size < 0 then
      invalid_arg "invalid HTTP connection limits" ;
    let input = {io; buffered= ""} in
    let rec loop () =
      match read_request input limits with
      | request -> (
          let close = request_wants_close request in
          let response =
            try handler request
            with _ -> Response.text ~status:500 "Internal server error\n"
          in
          match Response.websocket_upgrade response with
          | Some upgrade -> serve_websocket input request response upgrade
          | None ->
              write_string io
                (Http.serialize_response ~request_method:request.meth ~close
                   response ) ;
              if not close then loop () )
      | exception Clean_eof -> ()
      | exception Protocol_error error ->
          write_string io
            (Http.serialize_response ~request_method:"GET" ~close:true
               (error_response error) )
    in
    loop ()
end
