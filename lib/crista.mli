(**
    Crista is a small direct-style HTTP/1.0 and HTTP/1.1 server framework.

    The library is router-agnostic: an application supplies a function that
    turns each {!Request.t} into a {!Response.t}. {!Miou_server} provides the
    default Miou-based TCP server, while {!Connection} supports other
    byte-stream transports.
*)
module Headers = Headers

module Request = Request
module Response = Response
module Http = Http
module Connection = Connection
module Miou_server = Miou_server

type handler = Request.t -> Response.t
