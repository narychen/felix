(** Type generator *)

open Flx_types
open Flx_mtypes2

val gen_types :
  sym_state_t ->
  fully_bound_symbol_table_t ->
  (int * btypecode_t) list -> string

val gen_type_names :
  sym_state_t ->
  fully_bound_symbol_table_t ->
  (int * btypecode_t) list -> string