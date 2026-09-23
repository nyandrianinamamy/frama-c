open Cil_types

class vis = object(self)
  inherit Visitor.frama_c_inplace

  method! vstmt_aux s =
    match s.skind with
    | UnspecifiedSequence s ->
      let b = Cil.block_from_unspecified_sequence s in
      ignore (Visitor.visitFramacBlock (self:>Visitor.frama_c_visitor) b);
      Cil.SkipChildren
    | _ -> Cil.DoChildren

  method! vvrbl vi =
    Kernel.result "%s -> %a" vi.vname Fileloc.pretty vi.vdecl;
    Cil.DoChildren

end

let main () =
  Ast.compute ();
  Visitor.visitFramacFileSameGlobals (new vis) (Ast.get ())

let () =
  Boot.Main.extend main
