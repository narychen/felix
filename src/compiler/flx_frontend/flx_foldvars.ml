open Flx_util
open Flx_ast
open Flx_types
open Flx_print
open Flx_set
open Flx_mtypes2
open Flx_typing
open Flx_mbind
open Flx_srcref
open List
open Flx_unify
open Flx_treg
open Flx_generic
open Flx_maps
open Flx_exceptions
open Flx_use
open Flx_child
open Flx_reparent
open Flx_spexes

let string_of_intset s =
  "{ " ^
  IntSet.fold (fun i x -> x ^ si i ^ " ") s "" ^
  "}"


let ident x = x

let useset uses i =
  let u = try Hashtbl.find uses i with Not_found -> [] in
  fold_left (fun s (i,_) -> IntSet.add i s) IntSet.empty u

(* remove all uses of j from i *)
let remove_uses uses i j =
  (*
  print_endline "Eliding " ^ si i ^ " from " ^ si j);
  *)
  try
    let u = Hashtbl.find uses i in
    let u = filter (fun (k,sr) -> j <> k) u in
    Hashtbl.replace uses i u
  with Not_found -> ()

let add_use uses i j sr =
  let u = try Hashtbl.find uses i with Not_found -> [] in
  Hashtbl.replace uses i ((j,sr) :: u)


(* find all the variables of a function i which
   are not used by children, this is the kids
   minus just the union of everything used by the
   child functions.
*)
let locals child_map uses i =
  let kids = intset_of_list (find_children child_map i) in
  (*
  print_endline ("Kid of " ^ si i ^ " = " ^ string_of_intset kids);
  *)
  (*
  let u = useset uses i in
  *)
  let u = Flx_call.child_use_closure kids uses i in
  let unused_kids = IntSet.diff kids u in
  (*
  print_endline ("Unused kids are " ^ si i ^ " = " ^ string_of_intset unused_kids);
  *)
  let used_kids = IntSet.diff kids unused_kids in
  (*
  print_endline ("Used kids are " ^ si i ^ " = " ^ string_of_intset used_kids);
  *)
  (*
  let desc = descendants child_map i in
  *)
  let desc =
    IntSet.fold
    (fun j s -> let u = descendants child_map j in IntSet.union u s)
    used_kids
    IntSet.empty
  in
  (*
  print_endline ("Descendants of " ^ si i ^ " = " ^ string_of_intset desc);
  *)
  let u =
    IntSet.fold
    (fun j s ->
      let u = useset uses j in
      (*
      print_endline ("Descendant " ^ si j ^ " of " ^ si i ^ " uses " ^ string_of_intset u);
      *)
      IntSet.union s u
    )
    desc
    IntSet.empty
  in
  (*
  print_endline ("Stuff used by some descendant = " ^ string_of_intset u);
  *)
  IntSet.diff kids u


let fold_vars syms (uses,child_map,bbdfns) i ps exes =
  let pset = fold_left (fun s {pindex=i}-> IntSet.add i s) IntSet.empty ps in
  let kids = find_children child_map i in
  let id,_,_,_ = Hashtbl.find bbdfns i in
  (*
  print_endline ("\nFOLDing " ^ id ^ "<" ^ si i ^">");
  print_endline ("Kids = " ^ catmap ", " si kids);
  *)
  let descend = descendants child_map i in
  (*
  print_endline ("Descendants are " ^ string_of_intset descend);
  *)
  let locls = locals child_map uses i in
  (*
  print_endline ("Locals of " ^ si i ^ " are " ^ string_of_intset locls);
  print_endline "INPUT Code is";
  iter (fun exe -> print_endline (string_of_bexe syms.dfns 0 exe)) exes;
  *)

  let elim_pass exes =
    let count = ref 0 in
    let rec find_tassign inexes outexes =
      match inexes with
      | [] -> rev outexes
      | ((
        `BEXE_init (_,j,y)
        | `BEXE_assign (_, (`BEXPR_name (j,_),_),y)
      ) as x) :: t  when IntSet.mem j locls ->

        let id,_,_,_ = Hashtbl.find bbdfns j in
        (*
        print_endline ("CONSIDERING VARIABLE " ^ id ^ "<" ^ si j ^ "> -> " ^ sbe syms.dfns bbdfns y);
        *)
        (* does uses include initialisations or not ..?? *)

        (* check if the variable is used by any descendants *)
        let nlocal_uses =
          IntSet.fold
          (fun child u ->
             let luses = Flx_call.use_closure uses child in
             u || IntSet.mem j luses
          )
          descend
          false
        in
        if nlocal_uses then begin
          (*
          print_endline "VARIABLE USED NONLOCALLY";
          *)
          find_tassign t (x::outexes)
        end else

        (* count all local uses of the variable: there are no others *)
        let usecnt =
          let luses = try Hashtbl.find uses i with Not_found -> [] in
          fold_left (fun u (k,sr) -> if k = j then u+1 else u) 0 luses
         in
        (*
        print_endline ("Use count = " ^ si usecnt);
        *)
        let setcnt = ref (if IntSet.mem j pset then 2 else 1) in
        let sets exe =
          match exe with
           | `BEXE_init (_,k,_) when j = k -> incr setcnt
           | _ -> ()
        in
        iter sets t; iter sets outexes;
        (*
        print_endline ("Set count = " ^ si !setcnt);
        *)
        (* Lets not get too fancy .. fancy didn't work! *)
        let yuses = Flx_call.expr_uses_unrestricted syms descend uses y in
        (*
        print_endline ("Usage (unrestricted) = " ^ string_of_intset yuses_ur);
        print_endline ("restriction = " ^ string_of_intset pset);
        let yuses = Flx_call.expr_uses syms descend uses pset y in
        print_endline ("Usage (restricted) = " ^ string_of_intset yuses);
        *)
        let delete_var () =
          let id,_,_,_ = Hashtbl.find bbdfns j in
          if syms.compiler_options.print_flag then
            print_endline ("ELIMINATING VARIABLE " ^ id ^ "<" ^ si j ^ "> -> " ^ sbe syms.dfns bbdfns y);

          (* remove the variable *)
          Hashtbl.remove bbdfns j;
          remove_child child_map i j;
          remove_uses uses i j;
          incr count
        in
        let isvar =
          match Hashtbl.find bbdfns j with
          | _,_,_,(`BBDCL_var _ | `BBDCL_tmp _ | `BBDCL_ref _ ) -> true
          | _,_,_,`BBDCL_val _ -> false
          | _ -> assert false
        in

        (* Cannot do anything with variables or multiply assigned values
          so skip to next instruction -- this is a tail-recursive call
        *)
        if isvar or !setcnt > 1 then begin
          (*
          print_endline "IS VAR or SETCNT > 1";
          *)
          find_tassign t (x::outexes)

        (* otherwise it is a value and it is set at most once *)

        (* it is not used anywhere (except the init) *)
        end else if usecnt = 1 then begin
          if syms.compiler_options.print_flag then
          print_endline ("WARNING: unused variable "^si j^" found ..");
          delete_var();
          find_tassign t outexes

        (* OK, it is used at least once *)
        end else
        (* count elision of the init as 1 *)
        let rplcnt = ref 1 in
        let subi,rplimit =
          match y with
          | `BEXPR_tuple ys,_ ->
            (*
            print_endline "Tuple init found";
            print_endline ("initialiser y =" ^ sbe syms.dfns bbdfns y);
            print_endline ("Y uses = " ^ string_of_intset yuses);
            *)
            let rec subi j ys e =
              match map_tbexpr ident (subi j ys) ident e with
              | `BEXPR_get_n (k, (`BEXPR_name(i,_),_) ),_
                when j = i ->
                if syms.compiler_options.print_flag then
                print_endline ("[flx_fold_vars: tuple init] Replacing " ^ sbe syms.dfns bbdfns e ^
                  " with " ^ sbe syms.dfns bbdfns (nth ys k)
                );
                incr rplcnt; nth ys k
              | x -> x
            in subi j ys, length ys + 1
          | _ ->
            let rec subi j y e =
              match map_tbexpr ident (subi j y) ident e with
              | `BEXPR_name (i,_),_ when j = i -> incr rplcnt; y
              | x -> x
            in subi j y, 2 (* take init into account *)
        in
        let elimi exe =
          map_bexe ident subi ident ident ident exe
        in
        let subs = ref true in
        let elim exes = map
          (fun exe ->
          (*
          print_endline ("In Exe = " ^ string_of_bexe syms.dfns 2 exe);
          *)
          if !subs then
          match exe with
          | `BEXE_axiom_check _ -> assert false

          (* terminate substitution, return unmodified instr *)
          | `BEXE_goto _
          | `BEXE_proc_return _
          | `BEXE_label _
             -> subs:= false; exe

          (* return unmodified instr *)
          | `BEXE_begin
          | `BEXE_end
          | `BEXE_nop _
          | `BEXE_code _
          | `BEXE_nonreturn_code _
          | `BEXE_comment _
          | `BEXE_halt _
          | `BEXE_trace _
             -> exe

          (* conditional, check if y depends on init (tail rec) *)

          | `BEXE_assign (_,(`BEXPR_name (k,_),_),_)
          | `BEXE_svc (_,k)
          | `BEXE_init (_,k,_) ->
             (* an assignment a,b=b,a is turned into
                tmp = b,a;
                a = tmp.(0);
                b = tmp.(1);
              We have to prevent tmp being substituted away!
              So we should be getting k in yuses, for example,
              a should be in the uses of tmp since tmp = b,a.
             *)
             (*
             print_endline ("Assignment of " ^ si k);
             print_endline ("Y uses = " ^ string_of_intset yuses);
             *)
             let can_replace = not (IntSet.mem k yuses) in
             subs := can_replace;
             (* we could actually allow THIS assignment to go
             thru .. but it might screw up parallel assignemnt
             weirdo checks so well be conservative
             *)
             if !subs then elimi exe else exe

          (* return modified instr *)
          | `BEXE_ifgoto _
          | `BEXE_assert _
          | `BEXE_assert2 _
             -> elimi exe

          (* terminate substitution, return modified instr *)
          | `BEXE_apply_ctor _
          | `BEXE_apply_ctor_stack _
          | `BEXE_assign _
          | `BEXE_fun_return _
          | `BEXE_yield _
          | `BEXE_jump _
          | `BEXE_jump_direct _
          | `BEXE_loop _
          | `BEXE_call_prim _
          | `BEXE_call _
          | `BEXE_call_direct _
          | `BEXE_call_method_direct _
          | `BEXE_call_method_stack _
          | `BEXE_call_stack _
             -> subs := false; elimi exe
          else exe
          )
          exes
        in
        let t' = elim t in
        if !rplcnt > rplimit then
          begin
            if syms.compiler_options.print_flag then
            print_endline (
              "Warning: replacement count " ^
              si !rplcnt ^
              " exceeds replacement limit " ^
              si rplimit
            );
            find_tassign t (x::outexes)
          end
        else if !rplcnt <> usecnt then
          begin
            if syms.compiler_options.print_flag then
            print_endline (
              "Warning: replacement count " ^
              si !rplcnt ^
              " not equal to usage count " ^
              si usecnt
            );
            find_tassign t (x::outexes)
          end
        else
          begin
            delete_var();
            (*
            print_endline ("DELETE VAR "^si j^", ELIMINATING Exe = " ^ string_of_bexe syms.dfns 0 x);
            *)
            find_tassign t' outexes
          end

      | h::t -> find_tassign t (h::outexes)
    in
    !count,find_tassign exes []
  in
  let master_count = ref 0 in
  let iters = ref 0 in
  let rec elim exes =
    let count,exes = elim_pass exes in
    incr iters;
    master_count := !master_count + count;
    if count > 0 then elim exes else exes
  in
  let exes = elim exes in

  (*
  if syms.compiler_options.print_flag then
  *)
  if !master_count > 0 then begin
    if syms.compiler_options.print_flag then
    print_endline ("Removed " ^ si !master_count ^" variables in " ^ si !iters ^ " passes");
    (*
    print_endline "OUTPUT Code is";
    iter (fun exe -> print_endline (string_of_bexe syms.dfns 0 exe)) exes;
    *)
  end
  ;
  exes