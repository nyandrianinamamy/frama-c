module Self =
  Plugin.Register
    (struct
      let name = "Test"
      let shortname = "test"
      let help = ""
    end)

module KFSetOption = Self.Kernel_function_set
    (struct
      let option_name = "-test-kfset"
      let arg_name = ""
      let help = ""
    end)


module FDSetOption = Self.Fundec_set
    (struct
      let option_name = "-test-fdset"
      let arg_name = ""
      let help = ""
    end)
module KFMapOption = Self.Kernel_function_map
    (Self.Value_int)
    (struct
      let option_name = "-test-kfmap"
      let arg_name = ""
      let help = ""
      let default = Kernel_function.Map.empty
    end)

module KFMMapOption = Self.Kernel_function_multiple_map
    (Self.Value_int)
    (struct
      let option_name = "-test-kfmmap"
      let arg_name = ""
      let help = ""
      let default = Kernel_function.Map.empty
    end)

let () =
  KFSetOption.add_set_hook
    begin fun old_ new_ ->
      Kernel.feedback "OLD: %a"
        (Cil_datatype.Kf.Set.pretty_text Kernel_function.pretty) old_;
      Kernel.feedback "NEW: %a"
        (Cil_datatype.Kf.Set.pretty_text Kernel_function.pretty) new_;
    end

let () =
  FDSetOption.add_set_hook
    begin fun old_ new_ ->
      Kernel.feedback "OLD: %a"
        (Cil_datatype.Fundec.Set.pretty_text Cil_datatype.Fundec.pretty) old_;
      Kernel.feedback "NEW: %a"
        (Cil_datatype.Fundec.Set.pretty_text Cil_datatype.Fundec.pretty) new_;
    end

let () =
  KFMapOption.add_set_hook
    begin fun old_ new_ ->
      let pp fmt (kf, _) = Format.fprintf fmt "%a" Kernel_function.pretty kf in
      let old_ = Cil_datatype.Kf.Map.bindings old_ in
      let new_ = Cil_datatype.Kf.Map.bindings new_ in
      Kernel.feedback "OLD: %a" (Pretty_utils.pp_list pp) old_ ;
      Kernel.feedback "NEW: %a" (Pretty_utils.pp_list pp) new_ ;
    end


let () =
  KFMMapOption.add_set_hook
    begin fun old_ new_ ->
      let pp fmt (kf, _) = Format.fprintf fmt "%a" Kernel_function.pretty kf in
      let old_ = Cil_datatype.Kf.Map.bindings old_ in
      let new_ = Cil_datatype.Kf.Map.bindings new_ in
      Kernel.feedback "OLD: %a" (Pretty_utils.pp_list pp) old_ ;
      Kernel.feedback "NEW: %a" (Pretty_utils.pp_list pp) new_ ;
    end
