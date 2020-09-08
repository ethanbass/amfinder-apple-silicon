(* CastANet - cImage.mli *)

open CExt
open CGUI
open Printf

module ImageOps = struct
  let crop ~src_x ~src_y ~edge:e pix =
    let dest = GdkPixbuf.create ~width:e ~height:e () in
    GdkPixbuf.copy_area ~dest ~src_x ~src_y pix;
    dest
      
  let resize ?(interp = `NEAREST) ~edge:e pix =
    let open GdkPixbuf in
    let scale_x = float e /. (float (get_width pix))
    and scale_y = float e /. (float (get_height pix)) in
    let dest = create ~width:e ~height:e () in
    scale ~dest ~scale_x ~scale_y ~interp pix;
    dest
end

(* Images are represented as mosaics of square tiles. *)
type tiles = { edge : int; matrix : GdkPixbuf.pixbuf Ext_Matrix.t }

(* Large tiles are used in the "zoomed in" area on the left side of the 
 * interface, while small tiles are drawn on the right side. *)
type sizes = { small : tiles; large : tiles }

(* Graphical properties (number of rows and columns, width/height, etc.). *)
type graph = {
  rows : int; cols : int;
  xini : int; yini : int;
  imgw : int; imgh : int;
  mutable cursor : int * int;
}

(* CastANet images consist of two mosaics of square tiles (to populate the two
 * sides of the interface), a set of multi-level annotations (defined by the
 * user or constrained by annotation rules), and graphical properties (to
 * ensure proper display on the main window). *)
type t = { fpath : string; sizes : sizes; table : CTable.table; graph : graph }


(* garbage? 
let annotation ~r ~c t = Ext_Matrix.get_opt (annotations t) r c
let is_valid ~r ~c t = Ext_Matrix.get_opt (Img_Mosaic.annotations t) r c <> None
 /end of garbage *)

(* Image currently being processed. *)
let active_image = ref None

(* Not sure if needed outside. *)
let get_active () = !active_image
let rem_active () = active_image := None

module Par = struct
  open Arg
  let edge = ref 236
  let image_path = ref None
  let set_image_path x = if Sys.file_exists x then image_path := Some x
  let usage = "castanet_editor.exe [OPTIONS] [IMAGE_PATH]"
  let specs = align [
    "--edge", Set_int edge, sprintf " Tile size (default: %d pixels)." !edge;
  ]
  let initialize () = parse specs set_image_path usage
end

module Info = struct
  let path t = t.fpath
  let basename t = Filename.basename (path t)
  let dirname t = Filename.dirname (path t)
end

module Img_Mosaic = struct
  let source t = function `W -> t.graph.imgw | `H -> t.graph.imgh
  let origin t = function `X -> t.graph.xini | `Y -> t.graph.yini
  let dim t = function `R -> t.graph.rows | `C -> t.graph.cols
  let annotations {table; _} = table
  let edge t = function
    | `SMALL -> t.sizes.small.edge 
    | `LARGE -> t.sizes.large.edge
  let tiles t = function
    | `SMALL -> t.sizes.small.matrix
    | `LARGE -> t.sizes.large.matrix
  let tile ~r ~c t typ = Ext_Matrix.get_opt (tiles t typ) r c
  let x ~c t typ = (origin t `X) + c * (edge t typ)
  let y ~r t typ = (origin t `Y) + r * (edge t typ)
  let cursor_pos t = t.graph.cursor
  let set_cursor_pos t pos = t.graph.cursor <- pos
end


(* Iterators *)
module Iter = struct
  let tiles f t typ = Ext_Matrix.iteri f (Img_Mosaic.tiles t typ)
end

let statistics img = CTable.statistics (Img_Mosaic.annotations img)


(* Interaction with the user interface. *)
module Img_UI_update = struct
  let set_coordinates =
    let set lbl =
      ksprintf lbl#set_label "<tt><small><b>%c:</b> %03d</small></tt>"
    in fun r c -> GUI_Coords.(set row 'R' r; set column 'C' c)
    
  let set_counters =
    Option.iter (fun img ->
      List.iter (fun (chr, num) ->
        GUI_Layers.set_label chr num
      ) (statistics img (GUI_levels.current ()))
    ) !active_image
    
  let blank_tile =
    Ext_Memoize.create ~label:"CImage.Img_UI_update.blank_tile" ~one:true
    (fun () ->
      let pix = GdkPixbuf.create ~width:180 ~height:180 () in
      GdkPixbuf.fill pix 0l; pix)

  let magnified_view () =
    Option.iter (fun img ->
      let cur_r, cur_c = Img_Mosaic.cursor_pos img in
      for i = 0 to 2 do
        for j = 0 to 2 do
          let r = cur_r + i - 1 and c = cur_c + j - 1 in
          let pixbuf = match Img_Mosaic.tile r c img `LARGE with
            | None -> blank_tile ()
            | Some x -> x
          in GUI_Magnify.tiles.(i).(j)#set_pixbuf pixbuf
        done
      done;  
    ) !active_image
end


(* Cairo surfaces for the painting functions below. *)
module Img_Surface = struct
  let square ?(alpha = 0.65) ~kind edge =
    assert (edge > 0); 
    let surface = Cairo.Image.(create ARGB32 ~w:edge ~h:edge) in
    let t = Cairo.create surface in
    Cairo.set_antialias t Cairo.ANTIALIAS_SUBPIXEL;
    let clr = match kind with 
      | `CURSOR -> "#cc0000" 
      | `RGB x -> x in
    let r, g, b = EColor.html_to_float clr
    and a = max (min alpha 1.0) 0.0 in
    Cairo.set_source_rgba t r g b a;
    let edge = float edge in
    Cairo.rectangle t 0.0 0.0 ~w:edge ~h:edge;
    Cairo.fill t;
    Cairo.stroke t;
    surface

  let joker = 
    let aux () =
      match !active_image with
      | None -> assert false (* does not happen. *)
      | Some img -> let edge = Img_Mosaic.edge img `SMALL in
        square ~kind:(`RGB "#aaffaa") edge
    in Ext_Memoize.create ~label:"Img_Surface.master" aux

  let cursor = 
    let aux () =
      match !active_image with
      | None -> assert false (* does not happen. *)
      | Some img -> let edge = Img_Mosaic.edge img `SMALL in
        square ~kind:`CURSOR edge
    in Ext_Memoize.create ~label:"Img_Surface.cursor" aux

  let pointer = 
    let create () = 
      match !active_image with
      | None -> assert false
      | Some img -> let edge = Img_Mosaic.edge img `SMALL in
        square ~kind:`CURSOR ~alpha:0.40 edge
    in Ext_Memoize.create ~label:"Img_Surface.pointer" create

  let layers =
    List.map (fun lvl ->
      let aux lvl () =
        match !active_image with
        | None -> assert false (* does not happen. *)
        | Some img -> let edge = Img_Mosaic.edge img `SMALL in   
          List.map2 (fun chr rgb ->
            chr, square ~kind:(`RGB rgb) edge
          ) (CAnnot.char_list lvl) (CLevel.colors lvl)
      in lvl, Ext_Memoize.create ~label:"Img_Surface.layers" (aux lvl)
    ) CLevel.flags

  let get = function
    | '*' -> joker ()
    | '.' -> cursor ()
    | chr -> let lvl = GUI_levels.current () in
      List.assoc chr (List.assoc lvl layers ()) 
end


(* Painting functions. *)
module Img_Paint = struct
  let white_background ?(sync = true) () =
    let t = GUI_Drawing.cairo () in
    Cairo.set_source_rgba t 1.0 1.0 1.0 1.0;
    let w = float (GUI_Drawing.width ()) 
    and h = float (GUI_Drawing.height ()) in
    Cairo.rectangle t 0.0 0.0 ~w ~h;
    Cairo.fill t;
    Cairo.stroke t;
    if sync then GUI_Drawing.synchronize ()

  let tiles ?(sync = true) () =
    Option.iter (fun img ->
      let pixmap = GUI_Drawing.pixmap ()
      and xini = Img_Mosaic.origin img `X
      and yini = Img_Mosaic.origin img `Y
      and edge = Img_Mosaic.edge img `SMALL in
      Iter.tiles (fun ~r ~c tile ->
        pixmap#put_pixbuf
          ~x:(xini + c * edge)
          ~y:(yini + r * edge)
          ~width:edge ~height:edge tile
      ) img `SMALL;
      if sync then GUI_Drawing.synchronize ()
    ) !active_image

  let tile ?(sync = false) r c =
    Option.iter (fun img ->
      Option.iter (fun tile ->
        (GUI_Drawing.pixmap ())#put_pixbuf
          ~x:(Img_Mosaic.x ~c img `SMALL)
          ~y:(Img_Mosaic.y ~r img `SMALL) tile;
        if sync then GUI_Drawing.synchronize ()
      ) (Img_Mosaic.tile r c img `SMALL)
    ) !active_image

  (* FIXME Unsafe function - not for use outside! *)
  let surface ?(sync = false) r c surface =
    Option.iter (fun img ->
      let t = GUI_Drawing.cairo () in
      let x = Img_Mosaic.x ~c img `SMALL 
      and y = Img_Mosaic.y ~r img `SMALL in
      Cairo.set_source_surface t surface (float x) (float y);
      Cairo.paint t;
      if sync then GUI_Drawing.synchronize ()
    ) !active_image

  let annot ?(sync = false) r c =
    Option.iter (fun img ->
      let typ = GUI_Layers.get_active ()
      and tbl = Img_Mosaic.annotations img
      and lvl = GUI_levels.current () in
      let draw = match typ with
        | '*' -> not (CTable.is_empty tbl lvl r c) (* Catches any annotation. *)
        | chr -> CTable.mem tbl lvl r c (`CHR chr) in
      if draw then begin
        surface r c (Img_Surface.get typ);
        if sync then GUI_Drawing.synchronize ()
      end
    ) !active_image

  let cursor ?(sync = false) () =
    Option.iter (fun img ->
      let r, c = Img_Mosaic.cursor_pos img in
      tile r c;
      surface r c (Img_Surface.get '.');
      if sync then GUI_Drawing.synchronize ()
    ) !active_image

  let active_layer ?(sync = true) () =
    Option.iter (fun img ->
      CTable.iter (fun ~r ~c _ ->
        tile r c;
        annot r c
      ) (Img_Mosaic.annotations img) (GUI_levels.current ());
      cursor ();
      let r, c = Img_Mosaic.cursor_pos img in
      Img_UI_update.set_coordinates r c;
      if sync then GUI_Drawing.synchronize ()
    ) !active_image
end


(* Keyboard-related actions. *)
module Img_Move = struct
  let apply f =
    match !active_image with
    | None -> assert false
    | Some img -> f img

  let run ~f_row ~f_col _ =
    Option.iter (fun img ->
      let r, c = Img_Mosaic.cursor_pos img in
      Img_Paint.tile r c;
      Img_Paint.annot r c;    
      let new_r, new_c = f_row r, f_col c in
      Img_Mosaic.set_cursor_pos img (new_r, new_c);
      Img_UI_update.set_coordinates new_r new_c;
      Img_UI_update.magnified_view ();
      (* GUI.update_active_toggles toggles; *)
      Img_Paint.cursor ();      
      GUI_Drawing.synchronize ()
    ) !active_image

  let left ?(jump = 1) = run
    ~f_row:(fun r -> r)
    ~f_col:(fun c -> 
      let f img =
        let nc = Img_Mosaic.dim img `C and c' = c - jump in
        if c' < 0 then (c' + nc) mod nc else
        if c' >= nc then c' mod nc else c'
      in apply f)

  let right ?(jump = 1) = run
    ~f_row:(fun r -> r)
    ~f_col:(fun c ->
      let f img =
        let nc = Img_Mosaic.dim img `C and c' = c + jump in
        if c' < 0 then (c' + nc) mod nc else
        if c' >= nc then c' mod nc else c'
      in apply f)

  let up ?(jump = 1) = run
    ~f_row:(fun r -> 
      let f img =
        let nr = Img_Mosaic.dim img `R and r' = r - jump in
        if r' < 0 then (r' + nr) mod nr else
        if r' >= nr then r' mod nr else r'
      in apply f)
    ~f_col:(fun c -> c)

  let down ?(jump = 1) = run
    ~f_row:(fun r ->
      let f img =
        let nr = Img_Mosaic.dim img `R and r' = r + jump in
        if r' < 0 then (r' + nr) mod nr else
        if r' >= nr then r' mod nr else r'
      in apply f)
    ~f_col:(fun c -> c)
end


module Create = struct
  let large_tile_matrix nr nc edge src =
    Ext_Matrix.init nr nc (fun r c ->
      let src_x = c * edge and src_y = r * edge in
      ImageOps.crop ~src_x ~src_y ~edge src |> ImageOps.resize ~edge:180
    )
    
  let small_tile_matrix edge = Ext_Matrix.map (ImageOps.resize ~edge)
    
  let annotations path tiles =
    let zip = Filename.remove_extension path ^ ".zip" in
    if Sys.file_exists zip then CTable.load zip |> Option.get (* FIXME *)
    else CTable.create (`MAT tiles) 
end

let create fpath =
  let uiw, uih = GUI_Drawing.(width (), height ()) in
  let pix = GdkPixbuf.from_file fpath in
  let imgw, imgh = GdkPixbuf.(get_width pix, get_height pix) in
  let edge = !Par.edge in
  let rows = imgh / edge and cols = imgw / edge in
  let large = Create.large_tile_matrix rows cols edge pix in
  let sub = min (uiw / cols) (uih / rows) in
  let small = Create.small_tile_matrix sub large in
  let table = Create.annotations fpath small in
  let graph = { rows; cols;
    imgw; imgh; cursor = (0, 0);
    xini = (uiw - sub * cols) / 2;
    yini = (uih - sub * rows) / 2;
  } and sizes = {
    small = {edge = sub; matrix = small};
    large = {edge = 180; matrix = large};
  } in
  let img = { fpath; sizes; graph; table } in
  CPalette.set_tile_edge sub;
  CLog.info "source image: '%s'" fpath;
  CLog.info "source image size: %d x %d pixels" imgw imgh;
  CLog.info "tile matrix: %d x %d; edge: %d pixels" rows cols edge;
  img
  
let digest t =
  sprintf "<small><tt> \
    <b>Image:</b> %s ▪ \
    <b>Size:</b> %d × %d pixels ▪ \
    <b>Tiles:</b> %d × %d</tt></small>" 
    (Info.basename t)
    (Img_Mosaic.source t `W) (Img_Mosaic.source t `H)
    (Img_Mosaic.dim t `R) (Img_Mosaic.dim t `C)

let save () =
  match !active_image with
  | None -> ()
  | Some img -> Info.path img
    |> Filename.remove_extension
    |> sprintf "%s.zip"
    |> CTable.save (Img_Mosaic.annotations img)

let load () =
  (* Retrieves an image path from the command line or from a file chooser. *)
  Par.initialize ();
  let path = match !Par.image_path with
    | None -> GUI_FileChooserDialog.run ()
    | Some path -> path in
  (* Displays the main window in order to retrieve drawing parameters. *)
  CGUI.window#show ();
  (* Loads the image, creates tiles and populates the main window. *)
  let t = create path in
  active_image := Some t;
  (* Draws background and tiles, then adds image info to the status bar. *)
  Img_Paint.white_background ~sync:false ();
  Img_Paint.tiles ();
  Img_Paint.cursor ();
  CGUI.status#set_label (digest t);
  at_exit save (* FIXME this may not be the ideal situation! *)


module Img_Tracker = struct
  let mem = ref None

  let erase ?(sync = false) img =
    Gaux.may (fun ((r, c) as pos) ->
      Img_Paint.tile r c;
      Img_Paint.annot r c;
      if pos = Img_Mosaic.cursor_pos img then Img_Paint.cursor ();
      if sync then GUI_Drawing.synchronize ()
    ) !mem

  let show ~r ~c img =
    erase img;
    if CTable.is_valid (Img_Mosaic.annotations img) ~r ~c then begin
      erase img;
      Img_Paint.tile r c;
      Img_Paint.surface r c (Img_Surface.pointer ());
      mem := Some (r, c)
    end;
    GUI_Drawing.synchronize ()
end


(* UI-based functions that trigger changes. *)
module Img_Trigger = struct
  let arrow_keys ev =
    let sym, modi = GdkEvent.Key.(keyval ev, state ev) in
    let jump = 
      if List.mem `CONTROL modi then 25 else
      if List.mem `SHIFT   modi then 10 else 1 in
    let out, f = match sym with
      | 65361 -> true, Img_Move.left ~jump
      | 65362 -> true, Img_Move.up ~jump
      | 65363 -> true, Img_Move.right ~jump
      | 65364 -> true, Img_Move.down ~jump
      | _     -> false, ignore
    in f [(* toggles *)];
    out

  let annotation_keys ev =
    begin try
      let key = Char.uppercase_ascii (GdkEvent.Key.string ev).[0] in
      CLog.info "Key pressed is %C" key;
      if CAnnot.mem (`CHR key) (GUI_levels.current ()) then (
        let is_active = GUI_Toggles.toggle key in
        (* Updates the icon accordingly. *)
        let style = if is_active then `RGBA else `GREY in
        GUI_Toggles.set_icon key (CIcon.get key style `LARGE)
      )
    with _ -> () end;
    false

  let mouse_click ev =
    Option.iter (fun img ->
      let open GdkEvent.Button in
      let x = truncate (x ev) - Img_Mosaic.origin img `X
      and y = truncate (y ev) - Img_Mosaic.origin img `Y
      and e = Img_Mosaic.edge img `SMALL in
      let r = y / e and c = x / e in
      if CTable.is_valid (Img_Mosaic.annotations img) ~r ~c then
        Img_Move.run ~f_row:(fun _ -> r) ~f_col:(fun _ -> c)  [(* toggles *)]
    )!active_image;
    false

  let mouse_move ev =
    Option.iter (fun img ->
      let open GdkEvent.Motion in
      let x = truncate (x ev) - Img_Mosaic.origin img `X
      and y = truncate (y ev) - Img_Mosaic.origin img `Y
      and e = Img_Mosaic.edge img `SMALL in
      Img_Tracker.show ~r:(y / e) ~c:(x / e) img
    ) !active_image;
    false
  
  let mouse_leave _ =
    Option.iter (Img_Tracker.erase ~sync:true) !active_image;
    false
end

(* Connect the events to the functions. *)
let initialize () =
  CGUI.window#event#connect#key_press Img_Trigger.arrow_keys;
  CGUI.window#event#connect#key_press Img_Trigger.annotation_keys;
  let connect = GUI_Drawing.area#event#connect in
  connect#button_press Img_Trigger.mouse_click;
  connect#motion_notify Img_Trigger.mouse_move;
  connect#leave_notify Img_Trigger.mouse_leave;

  ()


