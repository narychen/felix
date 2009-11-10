open Flx_util
open Flx_ast
open Flx_types
open Flx_mtypes2
open List
open Flx_maps
open Flx_lookup

let sr  = Flx_srcref.make_dummy "[flx_why] generated"

(* Hackery to find logic functions in the library *)
let find_function syms env name =
  let entries =
    try Some (lookup_name_in_env syms env sr name)
    with _ -> None
  in
  let entries = match entries with
    | Some (FunctionEntry ls) -> ls
    | Some (NonFunctionEntry _ ) ->
      print_endline ("[flx_why] Expected '" ^ name ^ "' to be function");
      []
    | None ->
      if syms.compiler_options.print_flag then
      print_endline ("[flx_why] Can't find logic function '" ^ name ^ "' ");
      []
  in
  let entries =
    filter (fun {base_sym=i} ->
      match
        try Some (Flx_sym_table.find syms.sym_table i)
        with Not_found -> None
      with
      | Some {symdef=SYMDEF_fun (_,args,res,ct,_,_) } ->
        begin match name,args,res with
        | "lnot",[TYP_name (_,"bool",[])],TYP_name (_,"bool",[]) -> true
        | _,[TYP_name (_,"bool",[]); TYP_name (_,"bool",[])],TYP_name (_,"bool",[]) -> true
        | _ -> false
        end
      | _ -> false
    )
    entries
  in
  match entries with
  | [{base_sym=i}] -> i
  | [] ->
      if syms.compiler_options.print_flag then
      print_endline ("WARNING: flx_why cannot find '" ^ name ^ "'");
      dummy_bid
  | _ ->
      print_endline ("WARNING: flx_why found too many '" ^ name ^ "'");
      dummy_bid

let find_logics syms root =
  let env = build_env syms (Some root) in
  let ff x = find_function syms env x in
  [
    ff "land", "and";
    ff "lor", "or";
    ff "implies", "->";
    ff "eq", "<->";
    ff "lnot", "not"
  ]

let mn s = Flx_name.cid_of_flxid s

let getname syms bsym_table i =
  try match Flx_sym_table.find syms.sym_table i with {id=id} -> mn id
  with Not_found ->
  try match Hashtbl.find bsym_table i with id,_,_,_ -> mn id
  with Not_found -> "index_" ^ Flx_name.cid_of_bid i

let flx_bool = BTYP_unitsum 2

let isbool2 t =
  reduce_type t = BTYP_array (flx_bool, flx_bool)

let rec why_expr syms bsym_table (e: tbexpr_t) =
  let ee e = why_expr syms bsym_table e in
  match e with
  | BEXPR_apply ((BEXPR_closure (i,ts),_),b),_ ->
    let id = getname syms bsym_table i in
    id ^ "_" ^ Flx_name.cid_of_bid i ^ "(" ^
    (
      match b with
      | BEXPR_tuple [],_ -> "void"
      | BEXPR_tuple ls,_ -> catmap ", " ee ls
      | x -> ee x
    ) ^
    ")"


  | BEXPR_apply (a,b),_ ->
     "apply(" ^ ee a ^ "," ^ ee b ^")"

  (* this probably isn't right, ignoring ts *)
  | BEXPR_closure (i,ts),_ ->
    let id = getname syms bsym_table i in
    id ^ "_" ^ Flx_name.cid_of_bid i

  (* this probably isn't right, ignoring ts *)
  | BEXPR_name (i,ts),_ ->
    let id = getname syms bsym_table i in
    id ^ "_" ^ Flx_name.cid_of_bid i

  | BEXPR_tuple ls,_ ->
    "(" ^ catmap ", " ee ls ^ ")"

  | BEXPR_literal x,_ -> begin match x with
    | AST_int (s,j) -> let j = Big_int.int_of_big_int j in si j
    | _ -> "UNKLIT"
    end
  | _ -> "UNKEXPR"


let rec why_prop syms bsym_table logics (e: tbexpr_t) =
  let ee e = why_expr syms bsym_table e in
  let ep e = why_prop syms bsym_table logics e in
  match e with
  | BEXPR_apply ((BEXPR_closure (i,ts),_),b),_ ->
    let op = try assoc i logics with Not_found -> "" in
    begin match op with
    | "and"
    | "or"
    | "->" ->
      begin match b with
      | BEXPR_tuple [x;y],t when isbool2 t ->
        ep x ^ " " ^ op ^ " " ^ ep y

      | _ -> failwith ("[flx_why] Wrong number or type of args to '" ^ op ^ "'")
      end

    | "<->" ->
      begin match b with
      | BEXPR_tuple [x;y],t when isbool2 t ->
        ep x ^ " " ^ op ^ " " ^ ep y

      | _ -> "true=" ^ ee e
      end


    | "not" -> op ^ " " ^ ep b

    | "" -> "true=" ^ ee e
    | _ -> assert false
    end
  | _ -> "true=" ^ ee e


let cal_bvs bvs =
  let tps = match bvs with
    | [] -> ""
    | [s,_] -> "'" ^ s ^ " "
    | ss -> "('" ^ catmap ", '" fst ss ^ ") "
  in tps

let emit_type syms bsym_table f index name sr bvs =
  let srt = Flx_srcref.short_string_of_src sr in
  output_string f ("(* type " ^ name ^ ", at "^srt^" *)\n");

  (* NOTE BUG: needs namespace qualifier mangled in! *)
  if name = "int" then
    output_string f ("(* type int" ^ " -- USE why's builtin *)\n\n")
  else
    let tps = cal_bvs bvs in
    output_string f ("type " ^ tps ^ name ^ "\n\n")

let rec cal_type syms bsym_table t =
  let ct t = cal_type syms bsym_table t in
  match t with
(*  | BTYP_lvalue t -> ct t ^ " lvalue " *)
  | BTYP_tuple [] -> "unit"
  | BTYP_void -> "unit" (* cheat *)
  | BTYP_unitsum 2 -> "bool"
  | BTYP_function (a,b) ->
    "(" ^ ct a ^ ", " ^ ct b ^ ") fn"

  | BTYP_inst (index,ts) ->
    let id,sr,parent,entry = Hashtbl.find bsym_table index in
    (* HACK! *)
    let ts = match ts with
      | [] -> ""
      | [t] -> cal_type syms bsym_table t ^ " "
      | ts -> "(" ^ catmap ", " ct ts ^ ")"
    in
    ts ^ id
  | BTYP_var (index,_) ->
    begin try
      let id,sr,parent,entry = Hashtbl.find bsym_table index
      in "'" ^ id
    with Not_found -> "'T" ^ Flx_name.cid_of_bid index
    end

  | _ -> "dunno"

let emit_axiom syms bsym_table logics f (k:axiom_kind_t) (name,sr,parent,kind,bvs,bps,e) =
  if k <> kind then () else
  let srt = Flx_srcref.short_string_of_src sr in
  let tkind,ykind =
    match kind with
    | Axiom -> "axiom", "axiom"
    | Lemma -> "lemma", "goal"
  in
  output_string f ("(* "^tkind^" " ^ name ^ ", at "^srt^" *)\n\n");
  output_string f (ykind ^ " " ^ name ^ ":\n");
  iter (fun {pkind=pkind; pid=pid; pindex=pindex; ptyp=ptyp} ->
    output_string f
    ("  forall " ^ pid ^ "_" ^ Flx_name.cid_of_bid pindex ^ ": " ^
      cal_type syms bsym_table ptyp ^ ".\n")
  )
  (fst bps)
  ;
  begin match e with
  | `BPredicate e ->
    output_string f ("    " ^ why_prop syms bsym_table logics e)

  | `BEquation (l,r) ->
    output_string f ("  " ^
      why_expr syms bsym_table l ^ " = " ^
      why_expr syms bsym_table r
    )

  end;
  output_string f "\n\n"

let emit_reduction syms bsym_table logics f (name,bvs,bps,el,er) =
  output_string f ("(* reduction " ^ name ^ " *)\n\n");
  output_string f ("axiom " ^ name ^ ":\n");
  iter (fun {pkind=pkind; pid=pid; pindex=pindex; ptyp=ptyp} ->
    output_string f
    ("  forall " ^ pid ^ "_" ^ Flx_print.string_of_bid pindex ^ ": " ^
      cal_type syms bsym_table ptyp ^ ".\n")
  )
  bps
  ;
  output_string f ("    " ^ why_expr syms bsym_table el);
  output_string f ("\n  = " ^ why_expr syms bsym_table er);
  output_string f "\n\n"


let emit_function syms bsym_table f index id sr bvs ps ret =
  let srt = Flx_srcref.short_string_of_src sr in
  output_string f ("(* function " ^ id ^ ", at "^srt^" *)\n");
  let name = mn id ^ "_" ^ Flx_print.string_of_bid index in
  let dom = match ps with
    | [] -> "unit"
    | _ -> catmap ", " (cal_type syms bsym_table) ps
  in
  let cod = cal_type syms bsym_table ret in
  output_string f ("logic " ^ name ^ ": " ^ dom ^ " -> " ^ cod ^ "\n\n")

let calps ps =
  let ps = fst ps in (* elide constraint *)
  let ps =
    map
    (* again a bit of a hack! *)
    (fun {pkind=pk; pid=name; pindex=pidx; ptyp=t} -> t)
    ps
  in ps

let unitt = BTYP_tuple []

let emit_whycode filename syms bsym_table root =
  let logics = find_logics syms root in
  let f = open_out filename in
  output_string f "(****** HACKS *******)\n";
(*  output_string f "type 'a lvalue  (* Felix lvalues *) \n"; *)
  output_string f "type dunno      (* translation error *)\n";
  output_string f "type ('a,'b) fn (* functions *)\n";
  output_string f "logic apply: ('a,'b) fn, 'a -> 'b (* application *)\n";
  output_string f "\n";

  output_string f "(****** ABSTRACT TYPES *******)\n";
  Hashtbl.iter
  (fun index (id,parent,sr,entry) -> match entry with
  | BBDCL_abs (bvs,qual,ct,breqs) ->
    emit_type syms bsym_table f index id sr bvs
  | _ -> ()
  )
  bsym_table
  ;

  output_string f "(****** UNIONS *******)\n";
  Hashtbl.iter
  (fun index (id,parent,sr,entry) -> match entry with
  | BBDCL_union (bvs,variants) ->
    emit_type syms bsym_table f index id sr bvs
  | _ -> ()
  )
  bsym_table
  ;

  output_string f "(****** STRUCTS *******)\n";
  Hashtbl.iter
  (fun index (id,parent,sr,entry) -> match entry with
  | BBDCL_cstruct (bvs,variants)
  | BBDCL_struct (bvs,variants) ->
    emit_type syms bsym_table f index id sr bvs
  | _ -> ()
  )
  bsym_table
  ;

  output_string f "(******* FUNCTIONS ******)\n";
  Hashtbl.iter
  (fun index (id,parent,sr,entry) -> match entry with
  | BBDCL_procedure (_,bvs,ps,_) ->
    let ps = calps ps in
    emit_function syms bsym_table f index id sr bvs ps unitt

  | BBDCL_function (_,bvs,ps,ret,_) ->
    let ps = calps ps in
    emit_function syms bsym_table f index id sr bvs ps ret

  | BBDCL_fun (_,bvs,ps,ret,_,_,_) ->
    emit_function syms bsym_table f index id sr bvs ps ret

  | BBDCL_proc (_,bvs,ps,_,_) ->
    emit_function syms bsym_table f index id sr bvs ps unitt

  | _ -> ()
  )
  bsym_table
  ;

  output_string f "(******* AXIOMS ******)\n";
  iter
  (emit_axiom syms bsym_table logics f Axiom)
  syms.axioms
  ;

  output_string f "(******* REDUCTIONS ******)\n";
  iter
  (emit_reduction syms bsym_table logics f)
  syms.reductions
  ;

  output_string f "(******* LEMMAS (goals) ******)\n";
  iter
  (emit_axiom syms bsym_table logics f Lemma)
  syms.axioms
  ;
  close_out f
  ;
