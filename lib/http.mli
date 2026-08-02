(** How the body of an HTTP request is framed on the wire. *)
type framing = Empty | Fixed of int | Chunked

(** Errors detected while parsing an HTTP request head. *)
type parse_error =
  [ `Bad_request of string
  | `Body_too_large
  | `Expectation_failed
  | `Headers_too_large
  | `Unsupported_transfer_encoding ]

(** [parse_request_head ~max_body_size input] parses an HTTP request head and
    returns the request together with its body framing. The body itself is not
    consumed. A fixed-length body larger than [max_body_size] is rejected. *)
val parse_request_head :
  max_body_size:int -> string -> (Request.t * framing, parse_error) result

(** [serialize_response ~request_method ~close response] serializes [response]
    as an HTTP/1.1 response and adds connection and content-length fields.
    Payloads are suppressed for [HEAD], 1xx, 204, and 304 responses.
    @raise Invalid_argument if a response header contains invalid field text. *)
val serialize_response :
  request_method:string -> close:bool -> Response.t -> string
