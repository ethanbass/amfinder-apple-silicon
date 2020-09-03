(* CastANet - cLevel.ml *)

type t = [
  | `COLONIZATION (* colonized vs non-colonized vs background                 *)
  | `ARB_VESICLES (* [arbuscules, vesicles] vs non-colonized vs background    *)
  | `ALL_FEATURES (* [ERH, [root, [arb, ves, IRH, hyphopodia]]] vs background *)
]

let available_levels = [`COLONIZATION; `ARB_VESICLES; `ALL_FEATURES]

let other = function
  | `COLONIZATION -> `ARB_VESICLES, `ALL_FEATURES
  | `ARB_VESICLES -> `COLONIZATION, `ALL_FEATURES
  | `ALL_FEATURES -> `COLONIZATION, `ARB_VESICLES

module Chars = struct
  let colonization = ['Y'; 'N'; 'X']
  let arb_vesicvle = ['A'; 'V'; 'N'; 'X']
  let all_features = ['A'; 'V'; 'I'; 'E'; 'H'; 'R'; 'X']
end

let chars = function
  | `COLONIZATION -> Chars.colonization
  | `ARB_VESICLES -> Chars.arb_vesicles
  | `ALL_FEATURES -> Chars.all_features  

module Colors = struct
  let colonization = ["#80b3ff"; "#bec8b7"; "#ffaaaa"]
  let arb_vesicles = ["#80b3ff"; "#afe9c6"; "#bec8b7"; "#ffaaaa"]
  let all_features = ["#80b3ff"; "#afe9c6"; "#ffeeaa"; "#eeaaff";
                      "#ffb380"; "#bec8b7"; "#ffaaaa" ]
end

let colors = function
  | `COLONIZATION -> Colors.colonization
  | `ARB_VESICLES -> Colors.arb_vesicles
  | `ALL_FEATURES -> Colors.all_features  
