type message = Text of string | Binary of string

type state = Open | Close_sent | Closed

type fragmented = {opcode: int; contents: Buffer.t; mutable length: int}

type utf8_validator =
  { mutable remaining: int
  ; mutable next_minimum: int
  ; mutable next_maximum: int }

type t =
  { read: bytes -> off:int -> len:int -> int
  ; write: string -> off:int -> len:int -> unit
  ; max_message_size: int
  ; mutable state: state
  ; mutable fragmented: fragmented option
  ; utf8: utf8_validator }

exception End_of_stream

exception Protocol_error of int * string

let is_valid_utf8 string =
  let length = String.length string in
  let continuation index =
    index < length
    &&
    let byte = Char.code string.[index] in
    byte land 0xc0 = 0x80
  in
  let rec loop index =
    if index = length then true
    else
      let first = Char.code string.[index] in
      if first <= 0x7f then loop (index + 1)
      else if first >= 0xc2 && first <= 0xdf then
        continuation (index + 1) && loop (index + 2)
      else if first = 0xe0 then
        index + 2 < length
        &&
        let second = Char.code string.[index + 1] in
        second >= 0xa0 && second <= 0xbf
        && continuation (index + 2)
        && loop (index + 3)
      else if
        (first >= 0xe1 && first <= 0xec) || first = 0xee || first = 0xef
      then
        continuation (index + 1)
        && continuation (index + 2)
        && loop (index + 3)
      else if first = 0xed then
        index + 2 < length
        &&
        let second = Char.code string.[index + 1] in
        second >= 0x80 && second <= 0x9f
        && continuation (index + 2)
        && loop (index + 3)
      else if first = 0xf0 then
        index + 3 < length
        &&
        let second = Char.code string.[index + 1] in
        second >= 0x90 && second <= 0xbf
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if first >= 0xf1 && first <= 0xf3 then
        continuation (index + 1)
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if first = 0xf4 then
        index + 3 < length
        &&
        let second = Char.code string.[index + 1] in
        second >= 0x80 && second <= 0x8f
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else false
  in
  loop 0

let reset_utf8 validator =
  validator.remaining <- 0 ;
  validator.next_minimum <- 0x80 ;
  validator.next_maximum <- 0xbf

let validate_utf8_byte validator byte =
  if validator.remaining > 0 then (
    if byte < validator.next_minimum || byte > validator.next_maximum then
      raise (Protocol_error (1007, "text message is not UTF-8")) ;
    validator.remaining <- validator.remaining - 1 ;
    validator.next_minimum <- 0x80 ;
    validator.next_maximum <- 0xbf )
  else if byte <= 0x7f then ()
  else if byte >= 0xc2 && byte <= 0xdf then validator.remaining <- 1
  else if byte = 0xe0 then (
    validator.remaining <- 2 ;
    validator.next_minimum <- 0xa0 )
  else if (byte >= 0xe1 && byte <= 0xec) || byte = 0xee || byte = 0xef then
    validator.remaining <- 2
  else if byte = 0xed then (
    validator.remaining <- 2 ;
    validator.next_maximum <- 0x9f )
  else if byte = 0xf0 then (
    validator.remaining <- 3 ;
    validator.next_minimum <- 0x90 )
  else if byte >= 0xf1 && byte <= 0xf3 then validator.remaining <- 3
  else if byte = 0xf4 then (
    validator.remaining <- 3 ;
    validator.next_maximum <- 0x8f )
  else raise (Protocol_error (1007, "text message is not UTF-8"))

let valid_close_code code =
  List.mem code
    [1000; 1001; 1002; 1003; 1007; 1008; 1009; 1010; 1011; 1012; 1013; 1014]
  || (code >= 3000 && code <= 4999)

let write_all websocket string =
  websocket.write string ~off:0 ~len:(String.length string)

let add_uint16 buffer value =
  Buffer.add_char buffer (Char.chr (value lsr 8)) ;
  Buffer.add_char buffer (Char.chr (value land 0xff))

let add_uint64 buffer value =
  for shift = 7 downto 0 do
    Buffer.add_char buffer (Char.chr ((value lsr (shift * 8)) land 0xff))
  done

let send_frame websocket ~opcode payload =
  let length = String.length payload in
  let buffer = Buffer.create (length + 10) in
  Buffer.add_char buffer (Char.chr (0x80 lor opcode)) ;
  if length <= 125 then Buffer.add_char buffer (Char.chr length)
  else if length <= 0xffff then (
    Buffer.add_char buffer (Char.chr 126) ;
    add_uint16 buffer length )
  else (
    Buffer.add_char buffer (Char.chr 127) ;
    add_uint64 buffer length ) ;
  Buffer.add_string buffer payload ;
  write_all websocket (Buffer.contents buffer)

let ensure_open websocket =
  match websocket.state with
  | Open -> ()
  | Close_sent | Closed -> invalid_arg "WebSocket is closing or closed"

let send_text websocket text =
  ensure_open websocket ;
  if not (is_valid_utf8 text) then invalid_arg "WebSocket text is not UTF-8" ;
  send_frame websocket ~opcode:1 text

let send_binary websocket data =
  ensure_open websocket ;
  send_frame websocket ~opcode:2 data

let ping websocket data =
  ensure_open websocket ;
  if String.length data > 125 then
    invalid_arg "WebSocket ping payload exceeds 125 bytes" ;
  send_frame websocket ~opcode:9 data

let close_payload code reason =
  if not (valid_close_code code) then
    invalid_arg "invalid WebSocket close code" ;
  if not (is_valid_utf8 reason) then
    invalid_arg "WebSocket close reason is not UTF-8" ;
  if String.length reason > 123 then
    invalid_arg "WebSocket close reason exceeds 123 bytes" ;
  let buffer = Buffer.create (String.length reason + 2) in
  add_uint16 buffer code ;
  Buffer.add_string buffer reason ;
  Buffer.contents buffer

let close ?(code = 1000) ?(reason = "") websocket =
  match websocket.state with
  | Open ->
      send_frame websocket ~opcode:8 (close_payload code reason) ;
      websocket.state <- Close_sent
  | Close_sent | Closed -> ()

let is_open websocket = websocket.state = Open

let really_read websocket bytes ~off ~len =
  let rec loop offset remaining =
    if remaining > 0 then
      let count = websocket.read bytes ~off:offset ~len:remaining in
      if count = 0 then raise End_of_stream
      else loop (offset + count) (remaining - count)
  in
  loop off len

let read_bytes websocket length =
  let bytes = Bytes.create length in
  really_read websocket bytes ~off:0 ~len:length ;
  bytes

let uint16 bytes =
  (Char.code (Bytes.get bytes 0) lsl 8) lor Char.code (Bytes.get bytes 1)

let payload_length websocket short =
  if short <= 125 then short
  else if short = 126 then (
    let length = uint16 (read_bytes websocket 2) in
    if length < 126 then
      raise (Protocol_error (1002, "non-minimal payload length")) ;
    length )
  else
    let bytes = read_bytes websocket 8 in
    if Char.code (Bytes.get bytes 0) land 0x80 <> 0 then
      raise (Protocol_error (1002, "invalid 64-bit payload length")) ;
    let limit = Int64.of_int max_int in
    let length = ref 0L in
    Bytes.iter
      (fun byte ->
        length :=
          Int64.logor
            (Int64.shift_left !length 8)
            (Int64.of_int (Char.code byte)) )
      bytes ;
    if !length < 65536L then
      raise (Protocol_error (1002, "non-minimal payload length")) ;
    if !length > limit then
      raise (Protocol_error (1009, "message is too large")) ;
    Int64.to_int !length

type frame = {fin: bool; opcode: int; payload: string}

let read_masked_payload websocket ~mask ~length ~validate_text =
  let payload = Buffer.create length in
  let bytes = Bytes.create (min 4096 (max 1 length)) in
  let rec loop offset =
    if offset < length then (
      let wanted = min (Bytes.length bytes) (length - offset) in
      let count = websocket.read bytes ~off:0 ~len:wanted in
      if count = 0 then raise End_of_stream ;
      for index = 0 to count - 1 do
        let byte =
          Char.code (Bytes.get bytes index)
          lxor Char.code (Bytes.get mask ((offset + index) land 3))
        in
        Bytes.set bytes index (Char.chr byte) ;
        if validate_text then validate_utf8_byte websocket.utf8 byte
      done ;
      Buffer.add_subbytes payload bytes 0 count ;
      loop (offset + count) )
  in
  loop 0 ; Buffer.contents payload

let read_frame websocket =
  let header = read_bytes websocket 2 in
  let first = Char.code (Bytes.get header 0) in
  let second = Char.code (Bytes.get header 1) in
  let fin = first land 0x80 <> 0 in
  let opcode = first land 0x0f in
  if first land 0x70 <> 0 then
    raise (Protocol_error (1002, "reserved frame bits are set")) ;
  if not (List.mem opcode [0; 1; 2; 8; 9; 10]) then
    raise (Protocol_error (1002, "reserved opcode")) ;
  if second land 0x80 = 0 then
    raise (Protocol_error (1002, "client frame is not masked")) ;
  let length = payload_length websocket (second land 0x7f) in
  if opcode >= 8 && ((not fin) || length > 125) then
    raise (Protocol_error (1002, "invalid control frame")) ;
  if opcode < 8 && length > websocket.max_message_size then
    raise (Protocol_error (1009, "message is too large")) ;
  ( match (opcode, websocket.fragmented) with
  | 0, None -> raise (Protocol_error (1002, "unexpected continuation frame"))
  | (1 | 2), Some _ ->
      raise (Protocol_error (1002, "data frame during fragmented message"))
  | 0, Some fragment
    when length > websocket.max_message_size - fragment.length ->
      raise (Protocol_error (1009, "message is too large"))
  | _ -> () ) ;
  let mask = read_bytes websocket 4 in
  let validate_text =
    match (opcode, websocket.fragmented) with
    | 1, None -> reset_utf8 websocket.utf8 ; true
    | 0, Some {opcode= 1; _} -> true
    | _ -> false
  in
  let payload = read_masked_payload websocket ~mask ~length ~validate_text in
  if validate_text && fin && websocket.utf8.remaining <> 0 then
    raise (Protocol_error (1007, "text message is not UTF-8")) ;
  {fin; opcode; payload}

let complete_message opcode payload =
  if opcode = 1 then (
    if not (is_valid_utf8 payload) then
      raise (Protocol_error (1007, "text message is not UTF-8")) ;
    Text payload )
  else Binary payload

let append_fragment websocket fragment payload =
  if String.length payload > websocket.max_message_size - fragment.length
  then raise (Protocol_error (1009, "message is too large")) ;
  Buffer.add_string fragment.contents payload ;
  fragment.length <- fragment.length + String.length payload

let handle_close websocket payload =
  if String.length payload = 1 then
    raise (Protocol_error (1002, "close payload has length one")) ;
  if String.length payload >= 2 then (
    let code = (Char.code payload.[0] lsl 8) lor Char.code payload.[1] in
    if not (valid_close_code code) then
      raise (Protocol_error (1002, "invalid close code")) ;
    let reason = String.sub payload 2 (String.length payload - 2) in
    if not (is_valid_utf8 reason) then
      raise (Protocol_error (1007, "close reason is not UTF-8")) ) ;
  if websocket.state = Open then send_frame websocket ~opcode:8 payload ;
  websocket.state <- Closed

let rec receive_message websocket =
  let frame = read_frame websocket in
  match frame.opcode with
  | 8 ->
      handle_close websocket frame.payload ;
      None
  | 9 ->
      if websocket.state = Open then
        send_frame websocket ~opcode:10 frame.payload ;
      receive_message websocket
  | 10 -> receive_message websocket
  | 0 -> (
    match websocket.fragmented with
    | None -> raise (Protocol_error (1002, "unexpected continuation frame"))
    | Some fragment ->
        append_fragment websocket fragment frame.payload ;
        if frame.fin then (
          websocket.fragmented <- None ;
          Some
            (complete_message fragment.opcode
               (Buffer.contents fragment.contents) ) )
        else receive_message websocket )
  | (1 | 2) as opcode -> (
    match websocket.fragmented with
    | Some _ ->
        raise (Protocol_error (1002, "data frame during fragmented message"))
    | None ->
        if frame.fin then Some (complete_message opcode frame.payload)
        else (
          websocket.fragmented <-
            Some
              { opcode
              ; contents= Buffer.create (String.length frame.payload)
              ; length= String.length frame.payload } ;
          let fragment = Option.get websocket.fragmented in
          Buffer.add_string fragment.contents frame.payload ;
          receive_message websocket ) )
  | _ -> assert false

let receive websocket =
  match websocket.state with
  | Closed -> None
  | Open | Close_sent -> (
    try receive_message websocket with
    | End_of_stream ->
        websocket.state <- Closed ;
        None
    | Protocol_error (code, reason) ->
        ( if websocket.state = Open then
            try send_frame websocket ~opcode:8 (close_payload code reason)
            with _ -> () ) ;
        websocket.state <- Closed ;
        None )

module Sha1 = struct
  let rotate_left value count =
    Int32.logor
      (Int32.shift_left value count)
      (Int32.shift_right_logical value (32 - count))

  let digest input =
    let input_length = String.length input in
    let bit_length = Int64.mul (Int64.of_int input_length) 8L in
    let padding = (56 - ((input_length + 1) mod 64) + 64) mod 64 in
    let message = Bytes.make (input_length + 1 + padding + 8) '\000' in
    Bytes.blit_string input 0 message 0 input_length ;
    Bytes.set message input_length '\x80' ;
    for index = 0 to 7 do
      Bytes.set message
        (Bytes.length message - 1 - index)
        (Char.chr
           (Int64.to_int
              (Int64.logand
                 (Int64.shift_right_logical bit_length (index * 8))
                 0xffL ) ) )
    done ;
    let h0 = ref 0x67452301l in
    let h1 = ref 0xefcdab89l in
    let h2 = ref 0x98badcfel in
    let h3 = ref 0x10325476l in
    let h4 = ref 0xc3d2e1f0l in
    let words = Array.make 80 0l in
    for block = 0 to (Bytes.length message / 64) - 1 do
      for index = 0 to 15 do
        let offset = (block * 64) + (index * 4) in
        words.(index) <-
          Int32.logor
            (Int32.shift_left
               (Int32.of_int (Char.code (Bytes.get message offset)))
               24 )
            (Int32.logor
               (Int32.shift_left
                  (Int32.of_int (Char.code (Bytes.get message (offset + 1))))
                  16 )
               (Int32.logor
                  (Int32.shift_left
                     (Int32.of_int
                        (Char.code (Bytes.get message (offset + 2))) )
                     8 )
                  (Int32.of_int (Char.code (Bytes.get message (offset + 3)))) ) )
      done ;
      for index = 16 to 79 do
        words.(index) <-
          rotate_left
            (Int32.logxor
               words.(index - 3)
               (Int32.logxor
                  words.(index - 8)
                  (Int32.logxor words.(index - 14) words.(index - 16)) ) )
            1
      done ;
      let a = ref !h0 in
      let b = ref !h1 in
      let c = ref !h2 in
      let d = ref !h3 in
      let e = ref !h4 in
      for index = 0 to 79 do
        let f, k =
          if index < 20 then
            ( Int32.logor (Int32.logand !b !c)
                (Int32.logand (Int32.lognot !b) !d)
            , 0x5a827999l )
          else if index < 40 then
            (Int32.logxor !b (Int32.logxor !c !d), 0x6ed9eba1l)
          else if index < 60 then
            ( Int32.logor (Int32.logand !b !c)
                (Int32.logor (Int32.logand !b !d) (Int32.logand !c !d))
            , 0x8f1bbcdcl )
          else (Int32.logxor !b (Int32.logxor !c !d), 0xca62c1d6l)
        in
        let temporary =
          Int32.add (rotate_left !a 5)
            (Int32.add f (Int32.add !e (Int32.add k words.(index))))
        in
        e := !d ;
        d := !c ;
        c := rotate_left !b 30 ;
        b := !a ;
        a := temporary
      done ;
      h0 := Int32.add !h0 !a ;
      h1 := Int32.add !h1 !b ;
      h2 := Int32.add !h2 !c ;
      h3 := Int32.add !h3 !d ;
      h4 := Int32.add !h4 !e
    done ;
    let output = Bytes.create 20 in
    List.iteri
      (fun word_index word ->
        for byte_index = 0 to 3 do
          Bytes.set output
            ((word_index * 4) + byte_index)
            (Char.chr
               (Int32.to_int
                  (Int32.logand
                     (Int32.shift_right_logical word ((3 - byte_index) * 8))
                     0xffl ) ) )
        done )
      [!h0; !h1; !h2; !h3; !h4] ;
    Bytes.unsafe_to_string output
end

module Base64 = struct
  let alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

  let encode input =
    let length = String.length input in
    let output = Buffer.create ((length + 2) / 3 * 4) in
    let rec loop index =
      if index < length then (
        let a = Char.code input.[index] in
        let b =
          if index + 1 < length then Char.code input.[index + 1] else 0
        in
        let c =
          if index + 2 < length then Char.code input.[index + 2] else 0
        in
        Buffer.add_char output alphabet.[a lsr 2] ;
        Buffer.add_char output alphabet.[((a land 3) lsl 4) lor (b lsr 4)] ;
        Buffer.add_char output
          ( if index + 1 < length then
              alphabet.[((b land 15) lsl 2) lor (c lsr 6)]
            else '=' ) ;
        Buffer.add_char output
          (if index + 2 < length then alphabet.[c land 63] else '=') ;
        loop (index + 3) )
    in
    loop 0 ; Buffer.contents output

  let value = function
    | 'A' .. 'Z' as character -> Some (Char.code character - Char.code 'A')
    | 'a' .. 'z' as character ->
        Some (Char.code character - Char.code 'a' + 26)
    | '0' .. '9' as character ->
        Some (Char.code character - Char.code '0' + 52)
    | '+' -> Some 62
    | '/' -> Some 63
    | _ -> None

  let decode input =
    let length = String.length input in
    if length = 0 || length mod 4 <> 0 then None
    else
      let output = Buffer.create (length / 4 * 3) in
      let rec loop index =
        if index = length then Some (Buffer.contents output)
        else
          match (value input.[index], value input.[index + 1]) with
          | Some a, Some b -> (
              let last = index + 4 = length in
              match (input.[index + 2], input.[index + 3]) with
              | '=', '=' when last && b land 15 = 0 ->
                  Buffer.add_char output (Char.chr ((a lsl 2) lor (b lsr 4))) ;
                  loop (index + 4)
              | third, '=' when last -> (
                match value third with
                | Some c when c land 3 = 0 ->
                    Buffer.add_char output
                      (Char.chr ((a lsl 2) lor (b lsr 4))) ;
                    Buffer.add_char output
                      (Char.chr (((b land 15) lsl 4) lor (c lsr 2))) ;
                    loop (index + 4)
                | _ -> None )
              | third, fourth -> (
                match (value third, value fourth) with
                | Some c, Some d ->
                    Buffer.add_char output
                      (Char.chr ((a lsl 2) lor (b lsr 4))) ;
                    Buffer.add_char output
                      (Char.chr (((b land 15) lsl 4) lor (c lsr 2))) ;
                    Buffer.add_char output
                      (Char.chr (((c land 3) lsl 6) lor d)) ;
                    loop (index + 4)
                | _ -> None ) )
          | _ -> None
      in
      loop 0
end

module For_connection = struct
  let create ~max_message_size ~read ~write =
    if max_message_size < 0 then
      invalid_arg "WebSocket maximum message size must be non-negative" ;
    { read
    ; write
    ; max_message_size
    ; state= Open
    ; fragmented= None
    ; utf8= {remaining= 0; next_minimum= 0x80; next_maximum= 0xbf} }

  let accept_key key =
    match Base64.decode key with
    | Some decoded when String.length decoded = 16 ->
        Some
          (Base64.encode
             (Sha1.digest (key ^ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")) )
    | _ -> None
end
