(* AMFinder - ui/uIPredictions.ml
 *
 * MIT License
 * Copyright (c) 2021 Edouard Evangelisti
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *)

open Scanf
open Printf
open Morelib

module type PARAMS = sig
    val parent : GWindow.window
    val packing : #GButton.tool_item_o -> unit
    val border_width : int
    val tooltips : GData.tooltips
end

module type S = sig
    val palette : GButton.tool_button
    val get_colors : unit -> string array
    val set_choices : string list -> unit
    val get_active : unit -> string option
    val overlay : GButton.toggle_tool_button
    val palette : GButton.tool_button
    val set_palette_update : (unit -> unit) -> unit
    val sr_image : GButton.toggle_tool_button
    val convert : GButton.tool_button
    val ambiguities : GButton.tool_button
end

let palette_db = ref []

let transparency = "B0"

let validate_color ?(default = "#ffffff" ^ transparency) s =
  ksscanf s (fun _ _ -> default) "#%02x%02x%02x" 
    (fun a b c -> sprintf "#%02x%02x%02x%s" a b c transparency)

let load () =
    List.fold_left (fun pal (id, clr) ->
        let colors = Array.map validate_color clr in
        (id, colors) :: pal
    ) [] AmfRes.palettes

let parse_html_color =
    let f n = max 0.0 @@ min 1.0 @@ float n /. 255.0 in
    fun s -> sscanf s "#%02x%02x%02x%02x" (fun r g b a -> f r, f g, f b, f a)

let draw_icon ?(digest = false) colors =
  let mul = if digest then 2 else 6 and h = 16 in
  let len = Array.length colors * mul in
  let surface = Cairo.Image.(create ARGB32 ~w:len ~h) in 
  let t = Cairo.create surface in
  Cairo.set_antialias t Cairo.ANTIALIAS_SUBPIXEL;
  Array.iteri (fun i clr ->
    let r, g, b, _ = parse_html_color clr in
    Cairo.set_source_rgba t r g b 1.0;
    Cairo.rectangle t (float (mul * i)) 0.0 ~w:(float mul) ~h:(float h);
    Cairo.fill t;
    Cairo.stroke t;
  ) colors;
  (* Draws the generated surface on a GtkPixmap. *)
  let pixmap = GDraw.pixmap ~width:len ~height:h () in
  let u = Cairo_gtk.create pixmap#pixmap in
  Cairo.set_source_surface u surface 0.0 0.0;
  Cairo.paint u;
  (* Retrieves the drawings as pixbuf. *)
  let pix = GdkPixbuf.create ~width:len ~height:h () in
  pixmap#get_pixbuf pix;
  pix


module TreeView = struct

    module Data = struct
        let cols = new GTree.column_list
        let name = cols#add Gobject.Data.string
        let colors = cols#add Gobject.Data.caml
        let pixbuf = cols#add Gobject.Data.gobject
        let store = GTree.list_store cols
    end

    module Cell = struct
        let name = GTree.cell_renderer_text [`WEIGHT `BOLD]
        let pixbuf = GTree.cell_renderer_pixbuf [`XALIGN 0.0; `YALIGN 0.5]
    end

    module VCol = struct
        let markup = GTree.view_column ~title:"Name"
            ~renderer:(Cell.name, ["text", Data.name]) ()
        let pixbuf = GTree.view_column ~title:"Palette"
            ~renderer:(Cell.pixbuf, ["pixbuf", Data.pixbuf]) ()
    end

end



module Aux = struct

    let markup_tool_button ~stock ~label ~packing () =
        let btn = GButton.tool_button ~packing () in
        btn#misc#set_sensitive false;
        let box = GPack.hbox ~spacing:2 ~packing:btn#set_label_widget () in
        ignore (GMisc.image ~width:25 ~stock ~packing:(box#pack ~expand:false) ());
        let markup = Printf.sprintf "<small>%s</small>" label in
        ignore (GMisc.label ~markup ~xalign:0.0 ~packing:box#add ());
        btn

    let markup_button ~icon ~label ~packing () =
        let btn = GButton.tool_button ~packing () in
        btn#misc#set_sensitive false;
        let box = GPack.hbox ~spacing:2 ~packing:btn#set_label_widget () in
        ignore (GMisc.image
            ~width:25 ~pixbuf:icon
            ~packing:(box#pack ~expand:false) ());
        let markup = Printf.sprintf "<small>%s</small>" label in
        ignore (GMisc.label ~markup ~xalign:0.0 ~packing:box#add ());
        btn

    let small_text = Printf.sprintf "<small>%s</small>"

    let markup_toggle_button ?(sensitive = false) ~pixbuf ~label ~packing () =
        let btn = GButton.toggle_tool_button ~packing () in
        btn#misc#set_sensitive sensitive;
        let box = GPack.hbox
            ~spacing:2
            ~packing:btn#set_label_widget () in
        let ico = GMisc.image
            ~width:25
            ~pixbuf
            ~packing:(box#pack ~expand:false) ()
        and lbl = GMisc.label
            ~markup:(small_text label)
            ~xalign:0.0
            ~packing:box#add ()
        in btn, lbl, ico



end



module Make (P : PARAMS) : S = struct

    let packing = P.packing

    module Activate = struct
        let dialog = 
            let dlg = GWindow.dialog
                ~parent:P.parent
                ~width:300
                ~height:100
                ~modal:true
                ~deletable:false
                ~resizable:false
                ~title:"Predictions"
                ~type_hint:`UTILITY
                ~destroy_with_parent:true
                ~position:`CENTER_ON_PARENT () in
            dlg#add_button_stock `CANCEL `CANCEL;
            dlg#add_button_stock `OK `OK;
            dlg#set_border_width P.border_width;
            dlg

        let combo, (store, data) = GEdit.combo_box_text 
            ~packing:dialog#vbox#add ()
    end

    let _ = UIHelper.separator packing

    let _ = UIHelper.label packing
        (sprintf "<b><small>%s</small></b>" AmfLang.en_predictions)

    let container =
        let item = GButton.tool_item ~packing () in
        GPack.hbox ~spacing:2 ~packing:item#add ()

    let overlay, overlay_label, overlay_icon = 
        Aux.markup_toggle_button
            ~sensitive:true
            ~pixbuf:(AmfRes.get `ATTACH 24)
            ~label:"Import" 
            ~packing ()

    let palette =
        let btn = GButton.tool_button ~packing () in
        btn#misc#set_sensitive false;
        let box = GPack.hbox
            ~spacing:2
            ~packing:btn#set_label_widget () in
        let _ = GMisc.image 
            ~width:25
            ~pixbuf:(AmfRes.get `PALETTE 24)
            ~packing:(box#pack ~expand:false) ()
        and _ = GMisc.label
            ~markup:(Aux.small_text "Palette")
            ~xalign:0.0
            ~yalign:0.5
            ~packing:box#add () in
        btn

    let palette_update = ref []
    let set_palette_update f = palette_update := f :: !palette_update

    let sr_image =
        let btn, lbl, ico = Aux.markup_toggle_button
            ~pixbuf:(AmfRes.get (`CAM false) 24)
            ~label:"SRGAN" ~packing () in 
        let callback () =
            let style = btn#get_active in
            ico#set_pixbuf (AmfRes.get (`CAM style) 24)
        in ignore (btn#connect#toggled ~callback);
        btn

    let convert = Aux.markup_button
        ~icon:(AmfRes.get `CONVERT 24)
        ~label:"Convert" ~packing ()

    let ambiguities = Aux.markup_button
        ~icon:(AmfRes.get `AMBIGUOUS 24)
        ~label:"Validate" ~packing ()

    let set_choices t =
        Activate.store#clear ();
        let has_elements = t <> [] in
        overlay#misc#set_sensitive has_elements;
        List.iter (fun x ->
            let row = Activate.store#append () in
            Activate.store#set ~row ~column:Activate.data x;     
        ) t;
        if has_elements then Activate.combo#set_active 0

    let get_active () =
        if overlay#get_active then (
            match Activate.combo#active_iter with
            | None -> None
            | Some row -> Some (Activate.store#get ~row ~column:Activate.data)
        ) else None
        

    let set_tooltip s =
        let text = sprintf "Current palette: %s" s in
        P.tooltips#set_tip ~text palette#coerce
 
    let dialog = 
        let dlg = GWindow.dialog
            ~parent:P.parent
            ~width:250
            ~height:200
            ~modal:true
            ~deletable:false
            ~resizable:false
            ~title:"Color Palettes"
            ~type_hint:`UTILITY
            ~destroy_with_parent:true
            ~position:`CENTER_ON_PARENT () in
        dlg#add_button_stock `OK `OK;
        dlg#vbox#set_border_width P.border_width;
        dlg

    let scroll = GBin.scrolled_window
        ~hpolicy:`NEVER
        ~vpolicy:`ALWAYS
        ~border_width:P.border_width
        ~packing:dialog#vbox#add ()

    let view =
        let tv = GTree.view
            ~model:TreeView.Data.store
            ~headers_visible:false
            ~packing:scroll#add () in
        tv#selection#set_mode `SINGLE;
        ignore (tv#append_column TreeView.VCol.markup);
        ignore (tv#append_column TreeView.VCol.pixbuf);
        tv

  let initialize =
    let aux () =
      let sel = ref None in
      List.iteri (fun i (id, colors) ->
        let id = String.capitalize_ascii id in
        let row = TreeView.Data.store#prepend () in
        if id = "Cividis" then sel := Some (id, colors, row);
        let set ~column x = TreeView.Data.store#set ~row ~column x in
        set ~column:TreeView.Data.name id;
        set ~column:TreeView.Data.colors colors;
        set ~column:TreeView.Data.pixbuf (draw_icon colors)
      ) (load ());
      Option.iter (fun (id, colors, row) ->
        set_tooltip id;
        view#selection#select_iter row
      ) !sel
    in Memoize.create ~label:"UIPredictions.Make" aux

  let get_selected_iter () =
    view#selection#get_selected_rows
    |> List.hd
    |> TreeView.Data.store#get_iter
    
  let get_colors () =
    let row = get_selected_iter () in
    TreeView.Data.store#get ~row ~column:TreeView.Data.colors

    let get_name () =
        let row = get_selected_iter () in
        TreeView.Data.store#get ~row ~column:TreeView.Data.name

    module Toolbox = struct
        let enable () =
            (* What if there is only one choice available? *)
            let result = Activate.dialog#run () in
            Activate.dialog#misc#hide ();
            if result = `OK then
                let enable row =
                    overlay_icon#set_pixbuf (AmfRes.get `DETACH 24);
                    overlay_label#set_label (Aux.small_text AmfLang.en_attach);
                    sr_image#misc#set_sensitive true;
                    palette#misc#set_sensitive true;
                    convert#misc#set_sensitive true;
                    ambiguities#misc#set_sensitive true;
                in Option.iter enable Activate.combo#active_iter
            else overlay#set_active false

        let disable () =
            sr_image#misc#set_sensitive false;
            palette#misc#set_sensitive false;
            convert#misc#set_sensitive false;
            ambiguities#misc#set_sensitive false;
            overlay_icon#set_pixbuf (AmfRes.get `ATTACH 24);
            overlay_label#set_label (Aux.small_text AmfLang.en_attach)
    end

    let _ =
        initialize ();
        let callback () =
            if overlay#get_active then Toolbox.enable ()
            else Toolbox.disable ()
        in ignore (overlay#connect#toggled ~callback);
        let callback () =
            let old_palname = get_name () in
            if dialog#run () = `OK then (
                let new_palname = get_name () in
                if new_palname <> old_palname then begin
                    set_tooltip new_palname;
                    List.iter (fun f -> f ()) !palette_update
                end;
                dialog#misc#hide ()
            )
        in palette#connect#clicked ~callback
end
