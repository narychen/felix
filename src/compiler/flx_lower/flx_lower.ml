type lower_state_t = {
  syms: Flx_mtypes2.sym_state_t;
  closure_state: Flx_mkcls.closure_state_t;
  use: Flx_call.usage_table_t;
}


let make_lower_state syms = {
  syms=syms;
  closure_state=Flx_mkcls.make_closure_state syms;
  use=Hashtbl.create 97;
}


(* Convenience function for printing debug statements. *)
let print_debug state msg =
  if state.syms.Flx_mtypes2.compiler_options.Flx_mtypes2.print_flag
  then print_endline msg


let remove_module_parents bsym_table =
  (* Remove module parents. *)
  Flx_bsym_table.iter begin fun bid bsym ->
    match Flx_bsym_table.find_parent bsym_table bid with
    | Some parent ->
        begin
          try
            match Flx_bsym_table.find_bbdcl bsym_table parent with
            | Flx_bbdcl.BBDCL_module ->
                Flx_bsym_table.remove bsym_table bid;
                Flx_bsym_table.add_root bsym_table bid bsym
            | _ -> ()
          with Not_found -> ()
        end
    | None -> ()
  end bsym_table


(* Prep the bsym_table for the backend by lowering and simplifying symbols. *)
let lower_bsym_table state bsym_table root_proc =
  (* We have to remove module parents before we can do code generation. *)
  remove_module_parents bsym_table;

  (* Wrap closures. *)
  print_debug state "//Generating primitive wrapper closures";
  Flx_mkcls.make_closures state.closure_state bsym_table;

  (* Mark which functions are using global state. *)
  print_debug state "//Finding which functions use globals";

  (* Remove unused symbols. *)
  let bsym_table = Flx_use.copy_used state.syms bsym_table in

  (* Mark all the global functions and values. *)
  Flx_global.set_globals bsym_table;

  (* Instantiate type classes. *)
  print_debug state "//instantiating";

  Flx_intpoly.cal_polyvars state.syms bsym_table;
  Flx_inst.instantiate
    state.syms
    bsym_table
    false
    root_proc
    state.syms.Flx_mtypes2.bifaces;

  (* fix up root procedures so if they're not stackable,
     then they need a heap closure -- wrappers require
     one or the other *)
  Flx_types.BidSet.iter begin fun i ->
    let bsym = Flx_bsym_table.find bsym_table i in
    match Flx_bsym.bbdcl bsym with
    | Flx_bbdcl.BBDCL_procedure (props,vs,p,exes) ->
        let props = ref props in

        if List.mem `Stackable !props then begin
          (* The procedure is stackable, so mark that we can use a stack
           * closure. *)
          if not (List.mem `Stack_closure !props)
          then props := `Stack_closure :: !props
        end else begin

          (* The procedure isn't stackable, so mark that it needs a heap
           * closure. *)
          if not (List.mem `Heap_closure !props)
          then props := `Heap_closure :: !props
        end;

        (* Make sure the procedure will get a stack frame. *)
        if not (List.mem `Requires_ptf !props)
        then props := `Requires_ptf :: !props;

        (* Update the procedure with the new properties. *)
        let bbdcl = Flx_bbdcl.bbdcl_procedure (!props, vs,p,exes) in
        Flx_bsym_table.update_bbdcl bsym_table i bbdcl
    | _ -> ()
  end !(state.syms.Flx_mtypes2.roots);

  bsym_table


(* Prep the bexes and symbols for the backend by lowering and simplifying
 * symbols. *)
let lower state bsym_table root_proc bids bexes =
  (* Wrap closures. *)
  print_debug state "//Generating primitive wrapper closures";
  let bids = Flx_mkcls.make_closure state.closure_state bsym_table bids in

  (* Mark which functions are using global state. *)
  print_debug state "//Finding which functions use globals";

  (* Remove unused symbols. *)
  (* FIXME: This is disabled because it deletes all the symbols.
  let bsym_table = Flx_use.copy_used state.syms bsym_table in
  *)

  (* Mark all the global functions and values. *)
  let symbols = Flx_global.set_globals_for_symbols
    bsym_table
    state.use
    bids
  in

  (* Instantiate type classes. *)
  print_debug state "//instantiating";

  Flx_intpoly.cal_polyvars state.syms bsym_table;
  Flx_inst.instantiate
    state.syms
    bsym_table
    false
    root_proc
    state.syms.Flx_mtypes2.bifaces;

  bsym_table, bids, bexes
