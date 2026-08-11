include Crista

module Flow = struct
  type t = Picos_io.Unix.file_descr

  let read descriptor bytes ~off ~len =
    Picos_io.Unix.read descriptor bytes off len

  let write descriptor string ~off ~len =
    let rec loop off len =
      if len > 0 then
        let written =
          Picos_io.Unix.write_substring descriptor string off len
        in
        if written = 0 then raise End_of_file
        else loop (off + written) (len - written)
    in
    loop off len
end

module Http_connection = Connection.Make (Flow)

let spawn function_ =
  let computation = Picos.Computation.create () in
  let fiber = Picos.Fiber.create ~forbid:false computation in
  Picos.Fiber.spawn fiber (fun _fiber ->
      Picos.Computation.capture computation function_ () )

let serve ?(backlog = 128) ?limits ?(address = Unix.inet_addr_loopback) ~port
    handler =
  if port < 0 || port > 65535 then invalid_arg "port must be 0..65535" ;
  let open Picos_io.Unix in
  let listener = socket ~cloexec:true PF_INET SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> close listener)
    (fun () ->
      setsockopt listener SO_REUSEADDR true ;
      set_nonblock listener ;
      bind listener (ADDR_INET (address, port)) ;
      listen listener backlog ;
      while true do
        let client, _peer = accept ~cloexec:true listener in
        set_nonblock client ;
        spawn (fun () ->
            Fun.protect
              ~finally:(fun () -> close client)
              (fun () -> Http_connection.serve ?limits client handler) )
      done )
