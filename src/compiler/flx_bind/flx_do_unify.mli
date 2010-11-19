(** check if the two types unify: update the
variable definitions in sym_state ??? Only
useful if type variables are global, which is
the function return type unknown variable case..
*)
val do_unify:
  Flx_types.bid_t ref ->
  Flx_mtypes2.typevarmap_t ->
  Flx_sym_table.t ->
  Flx_bsym_table.t ->
  Flx_btype.t ->
  Flx_btype.t ->
  bool
