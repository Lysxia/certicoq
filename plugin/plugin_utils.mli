
val string_of_chars : char list -> string

val chars_of_string : string -> char list

val extract_constant : Names.GlobRef.t -> string -> (((BasicAst.kername * char list) * Datatypes.nat) * int)

val debug_mappings : (((BasicAst.kername * char list) * Datatypes.nat) * int) -> unit

val help_msg : string