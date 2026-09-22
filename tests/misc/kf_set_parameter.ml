module Self =
  Plugin.Register
    (struct
      let name = "Test"
      let shortname = "test"
      let help = ""
    end)

module Option = Self.Kernel_function_set
    (struct
      let option_name = "-test-set"
      let arg_name = ""
      let help = ""
    end)

let () =
  Option.add_set_hook
    begin fun old_ new_ ->
      Kernel.feedback "OLD: %a"
        (Cil_datatype.Kf.Set.pretty_text Kernel_function.pretty) old_;
      Kernel.feedback "NEW: %a"
        (Cil_datatype.Kf.Set.pretty_text Kernel_function.pretty) new_;
    end
