include Crista

module Flow = struct
  type t = Eio.Flow.two_way_ty Eio.Resource.t

  let read flow bytes ~off ~len =
    try Eio.Flow.single_read flow (Cstruct.of_bytes ~off ~len bytes)
    with End_of_file -> 0

  let write flow string ~off ~len =
    Eio.Flow.write flow [Cstruct.of_string ~off ~len string]
end

module Http_connection = Connection.Make (Flow)

let serve ?(backlog = 128) ?limits ?(address = Unix.inet_addr_loopback) ~net
    ~port handler =
  if port < 0 || port > 65535 then invalid_arg "port must be 0..65535" ;
  Eio.Switch.run (fun switch ->
      let address = Eio_unix.Net.Ipaddr.of_unix address in
      let listener =
        Eio.Net.listen ~reuse_addr:true ~backlog ~sw:switch net
          (`Tcp (address, port))
      in
      Eio.Net.run_server ~on_error:raise listener (fun flow _peer ->
          Http_connection.serve ?limits (flow :> Flow.t) handler ) )
