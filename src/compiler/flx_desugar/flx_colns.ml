(* Desugaring
 *
 * Two routines: one to build interfaces from modules, and one to lift lambdas
 * and also blocks.
 *)

open List

open Flx_ast
open Flx_exceptions
open Flx_mtypes2
open Flx_options
open Flx_types
open Flx_util
open Flx_version

let ocs2flx r =
  let sex = Ocs2sex.ocs2sex r in
  (*
  print_endline "OCS scheme term converted to s-expression:";
  Sex_print.sex_print sex;
  *)
  let sr = Flx_srcref.dummy_sr in
  let flx = Flx_sex2flx.xstatement_t sr sex in
  (*
  print_endline "s-expression converted to Felix statement!";
  print_endline (string_of_statement 0 flx);
  *)
  flx


(* return the given filename as a singleton list,
 *  unless it starts with @, in which case return the
 * list of lines in it (rendered recursively) 
 * To support --import=@files,
 * instead of having to --import each one on the command line,
 * which I want mainly so I can split the grammar up into
 * multiple files, which I can't do with #include, since I 
 * can't do that with Dypgen at the moment..
 *)
let rec render path f = 
  if String.length f < 1 then failwith "Empty --import filename";
  if String.sub f 0 1 = "@" then
    let f = Flx_filesys.find_file ~include_dirs:path (String.sub f 1 (String.length f - 1))in
    let f = open_in f in
    let res = ref [] in
    try
      let rec aux () =
        let line = input_line f in
        res := !res @ render path line;
        aux ()
      in aux ()
    with End_of_file ->
    close_in f;
    !res
  else [f]


(* This routine does all the nasty work of trying to figure out
where a file is, and if there is a viable cached parse of it.
It loads the cache if possible, otherwise parses the file,
then saves the parse tree if possible.

The output is a pair consisting of the directory in which the
felix file was found (not the *.par file, which might be elsewhere)
and a list of STMT_* statements (raw straight from the parser).
*)

let include_file syms curpath inspec =
  let force = syms.compiler_options.force_recompile in
  let this_version = !Flx_version.version_data in
  let basename =
    let n = String.length inspec in
    if n <= 3 then inspec
    else
      let x = String.sub inspec (n-4) 4 in
      match x with
      | ".flx" | ".par" -> String.sub inspec 0 (n-4)
      | _ -> inspec

  in
  let include_dirs = syms.compiler_options.include_dirs in
  let tf =
     if if String.length inspec > 2 then String.sub inspec 0 2 = "./" else false then
       Flx_filesys.find_file ~include_dirs:[curpath] (basename ^ ".flx")
     else
       Flx_filesys.find_file ~include_dirs (basename ^ ".flx") 
  in
  let pf =
    try
     if if String.length inspec > 2 then String.sub inspec 0 2 = "./" else false then
        Flx_filesys.find_file ~include_dirs:[curpath] (basename ^ ".par")
      else
        Flx_filesys.find_file
          ~include_dirs:include_dirs
          (basename ^ ".par")
    with Flx_filesys.Missing_path _ ->
      (* It's okay if the .par file doesn't exist. *)
      ""
  in
  let include_name =
    Filename.chop_extension
    (if tf <> "" then tf else pf)
  in
  (* if the source file doesn't exist, its creation time is the heat death
     of the universe. If the dependent file doesn't exist, its creation
     time is the big bang, meaning it has existed for eternity and is therefore
     out of date
  *)
  let tf_mt = Flx_filesys.virtual_filetime Flx_filesys.big_crunch tf in
  let pf_mt = Flx_filesys.virtual_filetime Flx_filesys.big_bang pf in
  let cbt = this_version.build_time_float in
  let saveit sts =
      let pf =
        (Flx_filesys.mk_cache_name syms.compiler_options.cache_dir
          (try Filename.chop_extension basename with _ -> basename)
        ) ^ ".par"
      in
        let x = try Some (open_out_bin pf) with _ -> None in
        match x with
        | Some x ->
          if syms.compiler_options.print_flag then
          print_endline ("Written " ^ pf);
          Marshal.to_channel x this_version [];
          Marshal.to_channel x sts [];
          close_out x
        | None -> () (* can't write, don't worry *)
  in
  let parseit () =
    if syms.compiler_options.print_flag then print_endline ("Parsing " ^ tf);
    let auto_imports = List.concat (List.map (render include_dirs) syms.compiler_options.auto_imports) in
    let parser_state = List.fold_left
      (fun state file -> Flx_parse_driver.parse_file ~include_dirs state file)
      (Flx_parse_driver.make_parser_state ())
      (auto_imports @ [tf])
    in
(*
    let tree = List.rev (Flx_parse.parser_data parser_state) in
*)
    let tree = List.rev_map (fun scm -> ocs2flx scm) (Flx_parse_driver.parser_data parser_state) in
    let local_prefix = Filename.basename basename in
    let macro_state = Flx_macro.make_macro_state local_prefix syms.counter in
    let tree = Flx_macro.expand_macros macro_state tree in
    tree
  in
  let sts =
      (* -- no file ----------------------------------------- *)
    if tf_mt = Flx_filesys.big_crunch && pf_mt = Flx_filesys.big_bang then
        failwith
        (
          "No .flx or .par file for name " ^
          basename ^
          " found in path:\n" ^
          String.concat "; " include_dirs
        )

      (* -- parsed file is newer or text doesn't exist ------- *)
    else
      if mem include_name !(syms.include_files) then [] else
      begin (* file not already included *)
        syms.include_files := include_name :: !(syms.include_files)
        ;
        if cbt < pf_mt && (not force) && tf_mt < pf_mt then
        begin (* top level time stamps OK *)
          let x = open_in_bin pf in
          let that_version = Marshal.from_channel x in
          if this_version = that_version then begin
            let tree = Marshal.from_channel x in
            close_in x;
            if syms.compiler_options.print_flag then
            print_endline ("Loaded " ^ pf);
            tree
          end (* right version of compiler *)
          else
          begin (* wrong version of compiler *)
            close_in x;
            let sts = parseit() in
            saveit sts;
            sts
          end
        end
        else
        begin (* time stamps wrong *)
          let sts = parseit() in
          saveit sts;
          sts
        end
      end (* process inclusion first time *)
  in
    (Filename.dirname include_name), sts

