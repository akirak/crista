(** RFC 6455 WebSocket sessions. *)

(** A WebSocket connection. Values are supplied to handlers registered with
    {!Response.websocket}. *)
type t

type message =
  | Text of string
  | Binary of string
      (** A complete text or binary message. Fragmented wire messages are assembled
    before they are returned. *)

val receive : t -> message option
(** [receive websocket] waits for the next complete application message.
    Ping, pong, fragmentation, and the closing handshake are handled
    automatically. It returns [None] after a close frame, an end of stream, or
    a protocol error. *)

val send_text : t -> string -> unit
(** Sends one UTF-8 text message.
    @raise Invalid_argument if the string is not valid UTF-8. *)

val send_binary : t -> string -> unit
(** Sends one binary message. *)

val ping : t -> string -> unit
(** Sends a ping with at most 125 bytes of application data.
    @raise Invalid_argument if the data is too long. *)

val close : ?code:int -> ?reason:string -> t -> unit
(** Starts the closing handshake. [code] defaults to 1000 and [reason] to the
    empty string.
    @raise Invalid_argument if the code is not valid on the wire, the reason is
    not UTF-8, or the resulting control frame is too large. *)

val is_open : t -> bool
(** Whether application data can still be sent. *)

(** Internal hooks used by byte-stream connection implementations. They are
    public only so transports built outside Crista can perform an upgrade. *)
module For_connection : sig
  val create :
       max_message_size:int
    -> read:(bytes -> off:int -> len:int -> int)
    -> write:(string -> off:int -> len:int -> unit)
    -> t

  val accept_key : string -> string option
  (** Returns the RFC 6455 accept value when the supplied key is canonical
      base64 encoding of exactly 16 bytes. *)
end
