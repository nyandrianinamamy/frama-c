
module Self =
  Plugin.Register
    (struct
      let name = "Quoted parameters"
      let shortname = "qp"
      let help = ""
    end)

include Self

module DString = struct
  include Datatype.String
  let pp_map ppk ppv fmt v =
    Map.pretty ~item:"@[<hov 2>%a ->@ %a@]" ppk ppv fmt v
  let of_string str = [ str ]
  let to_string str = str
end

module String_key = struct
  include DString
  let of_string str = [ str ]
  let to_string str = str
end
module String_value = struct
  include DString
  let of_string str = str
  let to_string str = str
end

module QpMap = struct
  include Make_map
      (String_key)
      (String_value)
      (struct
        let option_name = "-qp-map"
        let help = ""
        let arg_name = ""
        let default = Datatype.String.Map.empty
        let dependencies = []
      end)
  let print fmt =
    Format.fprintf fmt "@[<hv 3>%a@]"
      (DString.pp_map DString.pretty DString.pretty) (get ())
end

module QpMultiMap = struct
  include Make_multiple_map
      (String_key)
      (String_value)
      (struct
        let option_name = "-qp-multi-map"
        let help = ""
        let arg_name = ""
        let default = DString.Map.empty
        let dependencies = []
      end)
  let print fmt =
    Format.fprintf fmt "@[<hv 3>%a@]"
      (DString.pp_map DString.pretty (List.pretty DString.pretty)) (get ())
end

let pp_filepath fmt fp =
  Format.pp_print_string fmt (Fclib.Filepath.to_string_abs ~quoted:false fp)

module QpFilepath (I : sig val option_name : string end) = struct
  include Filepath
      (struct
        let option_name = I.option_name
        let help = ""
        let arg_name = ""
        let existence = Fclib.Filepath.Indifferent
        let file_kind = ""
      end)
  let print fmt =
    let fp = get () in
    pp_filepath fmt fp
end
module QpFilepathLinux =
  QpFilepath (struct let option_name = "-qp-filepath-linux" end)
module QpFilepathWindows =
  QpFilepath (struct let option_name = "-qp-filepath-windows" end)
module QpFilepathWithSpace =
  QpFilepath (struct let option_name = "-qp-filepath-with-space" end)

module QpFilepathList = struct
  include Filepath_list (struct
      let option_name = "-qp-filepath-list"
      let help = ""
      let arg_name = ""
      let existence = Fclib.Filepath.Indifferent
      let file_kind = ""
    end)
  let print fmt =
    Format.fprintf fmt "@[<hv 2>%a@]"
      (List.pretty pp_filepath) (get ())
end

module QpFilepathMap = struct
  include Filepath_map
      (String_value)
      (struct
        let option_name = "-qp-filepath-map"
        let help = ""
        let arg_name = ""
        let default = Fclib.Filepath.Map.empty
        let existence = Fclib.Filepath.Indifferent
        let file_kind = ""
      end)
  let print fmt =
    let pp_map fmt v =
      Fclib.Filepath.Map.pretty ~item:"@[<hov 2>%a ->@ %a@]"
        pp_filepath DString.pretty fmt v
    in
    Format.fprintf fmt "@[<hv 3>%a@]" pp_map (get ())
end

let print_all () =
  feedback "@[<v 0>map:@ %t@]" QpMap.print;
  feedback "@[<v 0>multi-map:@ %t@]" QpMultiMap.print;
  feedback "@[<v 2>filepath linux:@ %t@]" QpFilepathLinux.print;
  feedback "@[<v 2>filepath windows:@ %t@]" QpFilepathWindows.print;
  feedback "@[<v 2>filepath with space:@ %t@]" QpFilepathWithSpace.print;
  feedback "@[<v 2>filepath list:@ %t@]" QpFilepathList.print;
  feedback "@[<v 2>filepath map:@ %t@]" QpFilepathMap.print;
  ()

let () =
  Fclib.Hpath.testing_mode ();
  Boot.Main.extend print_all
