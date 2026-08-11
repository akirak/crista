module Headers = Headers
module Request = Request
module Response = Response
module Websocket = Websocket
module Http = Http
module Connection = Connection

type handler = Request.t -> Response.t
