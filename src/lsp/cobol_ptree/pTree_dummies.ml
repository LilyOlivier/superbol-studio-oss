(**************************************************************************)
(*                                                                        *)
(*                        SuperBOL OSS Studio                             *)
(*                                                                        *)
(*  Copyright (c) 2022-2023 OCamlPro SAS                                  *)
(*                                                                        *)
(* All rights reserved.                                                   *)
(* This source code is licensed under the GNU Affero General Public       *)
(* License version 3 found in the LICENSE.md file in the root directory   *)
(* of this source tree.                                                   *)
(*                                                                        *)
(**************************************************************************)

(** Defines some dummy nodes that can be used to fill in missing parts of the
    parse tree. *)

open PTree_types
open Cobol_common.Srcloc.INFIX

let integer_zero = "0"
and integer_one = "1"
and alphanum__ = "_"

let dummy_loc =
  Cobol_common.Srcloc.dummy

let dummy_string = alphanum__ &@ dummy_loc

let dummy_name = dummy_string

let dummy_qualname: qualname =
  Name dummy_name

let dummy_qualname': qualname with_loc =
  dummy_qualname &@ dummy_loc

let dummy_qualident =
  {
    ident_name = dummy_qualname';
    ident_subscripts = [];
  }

let dummy_ident =
  QualIdent dummy_qualident

let dummy_literal =
  Integer integer_zero

let dummy_alphanum =
  {
    str = alphanum__;
    quotation = Double_quote;
    hexadecimal = false;
    runtime_repr = Native_bytes;
  }

let dummy_expr =
  Atom (Fig Zero)

let dummy_picture =
  {
    picture_string = "X" &@ dummy_loc;
    picture_locale = None;
    picture_depending = None;
  }

let dummy_picture_locale =
  {
    locale_name = None;
    locale_size = integer_zero;
  }

(* --- *)

let fixed_zero =
  {
    fixed_integral = integer_zero;
    fixed_fractional = integer_one;
  }

let floating_zero =
  {
    float_significand = fixed_zero;
    float_exponent = integer_one;
  }

let boolean_zero =
  {
    bool_base = `Bool;
    bool_value = integer_zero;
  }

(* --- *)

let strip_dummies_from_qualname =
  let rec aux: (Terms.qualname as 'a) -> 'a = function
    | Name _ as qn -> qn
    | Qual (n, qn) when n == dummy_name -> aux qn
    | Qual (n, qn) when qn == dummy_qualname -> Name n
    | Qual (n, qn) -> Qual (n, aux qn)
  in
  aux
