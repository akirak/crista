(**
    Crista is a small direct-style HTTP/1.0 and HTTP/1.1 server framework.

    The library is router-agnostic: an application supplies a function that
    turns each {!Request.t} into a {!Response.t}. The [crista-eio],
    [crista-picos], and [crista-miou] packages run the same handler with their
    respective concurrency systems, while {!Connection} supports custom
    byte-stream transports.
*)
module Headers = Headers

module Request = Request
module Response = Response
module Websocket = Websocket
module Http = Http
module Connection = Connection

(** A direct-style HTTP request handler. *)
type handler = Request.t -> Response.t
