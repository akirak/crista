type framing = Empty | Fixed of int | Chunked

type parse_error =
  [ `Bad_request of string
  | `Body_too_large
  | `Expectation_failed
  | `Headers_too_large
  | `Unsupported_transfer_encoding ]

val parse_request_head :
  max_body_size:int -> string -> (Request.t * framing, parse_error) result

val serialize_response :
  request_method:string -> close:bool -> Response.t -> string
