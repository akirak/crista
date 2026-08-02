type route =
  {meth: string option; path: string; handler: Request.t -> Response.t}

type t = route list ref

let create () = ref []

let add ?meth path handler router =
  let meth = Option.map String.uppercase_ascii meth in
  router := !router @ [{meth; path; handler}]

let get path handler router = add ~meth:"GET" path handler router

let post path handler router = add ~meth:"POST" path handler router

let route router request =
  let path = Request.path request in
  let matching_path = List.filter (fun route -> route.path = path) !router in
  match
    List.find_opt
      (fun route ->
        match route.meth with
        | None -> true
        | Some "GET" when String.equal request.meth "HEAD" -> true
        | Some meth -> String.equal meth request.meth )
      matching_path
  with
  | Some route -> route.handler request
  | None when matching_path = [] -> Response.text ~status:404 "Not found\n"
  | None ->
      let allowed =
        matching_path
        |> List.filter_map (fun route -> route.meth)
        |> List.sort_uniq String.compare
        |> String.concat ", "
      in
      Response.text ~status:405
        ~headers:(Headers.of_list [("allow", allowed)])
        "Method not allowed\n"
