module Flow = struct
  type t = Miou_unix.file_descr

  let read descriptor bytes ~off ~len =
    Miou_unix.read descriptor bytes ~off ~len

  let write descriptor string ~off ~len =
    Miou_unix.write descriptor string ~off ~len
end

module Http_connection = Connection.Make (Flow)

let rec reap orphans =
  match Miou.care orphans with
  | None | Some None -> ()
  | Some (Some promise) ->
      ignore (Miou.await promise) ;
      reap orphans

let serve ?(backlog = 128) ?limits ?(address = Unix.inet_addr_loopback) ~port
    handler =
  if port < 0 || port > 65535 then invalid_arg "port must be 0..65535" ;
  let listener = Miou_unix.tcpv4 () in
  Fun.protect
    ~finally:(fun () -> Miou_unix.close listener)
    (fun () ->
      Miou_unix.bind_and_listen ~backlog listener
        (Unix.ADDR_INET (address, port)) ;
      let orphans = Miou.orphans () in
      while true do
        reap orphans ;
        let client, _peer = Miou_unix.accept listener in
        ignore
          (Miou.async ~orphans (fun () ->
               Fun.protect
                 ~finally:(fun () -> Miou_unix.close client)
                 (fun () -> Http_connection.serve ?limits client handler) )
          )
      done )

let run ?domains ?backlog ?limits ?address ~port handler =
  Miou_unix.run ?domains (fun () ->
      serve ?backlog ?limits ?address ~port handler )
