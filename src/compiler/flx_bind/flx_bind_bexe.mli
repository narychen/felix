(** Bind executable statements *)

type bexe_state_t

val make_bexe_state:
  ?parent:Flx_types.bid_t ->    (** The parent symbol's index *)
  ?env:Flx_mtypes2.env_t ->     (** The local symbol lookup table *)
  Flx_types.bid_t ref ->        (** fresh bid counter *)
  Flx_sym_table.t ->            (** The symbol table *)
  Flx_lookup.lookup_state_t ->  (** The state needed for lookup *)
  Flx_types.bvs_t ->            (** The parent symbol's bound type variables *)
  Flx_btype.t ->                (** The expected return type *)
  bexe_state_t

(** Bind an executable that's inside of a function. *)
val bind_exe:
  bexe_state_t ->             (** The state needed to bind the exe. *)
  Flx_bsym_table.t ->
  (Flx_bexe.t -> 'a -> 'a) -> (** Map this function over the bound exes *)
  Flx_ast.sexe_t ->           (** The executable to bind *)
  'a ->                       (** The init value *)
  'a

(** Bind a series of executables that are inside of a function. *)
val bind_exes:
  bexe_state_t ->             (** The state needed to bind the exes. *)
  Flx_bsym_table.t ->
  Flx_srcref.t ->             (** The parent's srcref. *)
  Flx_ast.sexe_t list ->      (** The list of executables to bind. *)
  Flx_btype.t * Flx_bexe.t list
