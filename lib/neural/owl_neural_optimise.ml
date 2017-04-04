(*
 * OWL - an OCaml numerical library for scientific computing
 * Copyright (c) 2016-2017 Liang Wang <liang.wang@cl.cam.ac.uk>
 *)

open Owl_algodiff_ad


module Learning_Rate = struct

  type typ =
    | Adagrad   of float
    | Const     of float
    | Decay     of float * float
    | Exp_decay of float * float
    | RMSprop   of float * float
    | Schedule  of float array

  let run = function
    | Adagrad a        -> fun _ g c -> Maths.(F a / sqrt (c + F 1e-8))
    | Const a          -> fun _ _ _ -> F a
    | Decay (a, k)     -> fun i _ _ -> Maths.(F a / (F 1. + F k * (F (float_of_int i))))
    | Exp_decay (a, k) -> fun i _ _ -> Maths.(F a * exp (neg (F k) * (F (float_of_int i))))
    | RMSprop (a, k)   -> fun _ g c -> Maths.(F a / sqrt (c + F 1e-6))
    | Schedule a       -> fun i _ _ -> F a.(i mod (Array.length a))

  let default = function
    | Adagrad _   -> Adagrad 0.01
    | Const _     -> Const 0.001
    | Decay _     -> Decay (0.1, 0.1)
    | Exp_decay _ -> Exp_decay (1., 0.1)
    | RMSprop _   -> RMSprop (0.001, 0.9)
    | Schedule _  -> Schedule [|0.001|]

  let update_ch typ gs ch = match typ with
    | Adagrad _      -> Owl_utils.aarr_map2 (fun g c -> Maths.(c + g * g)) gs ch
    | RMSprop (a, k) -> Owl_utils.aarr_map2 (fun g c -> Maths.((F k * c) + (F 1. - F k) * g * g)) gs ch
    | _              -> ch

  let to_string = function
    | Adagrad a        -> Printf.sprintf "adagrad %g" a
    | Const a          -> Printf.sprintf "constant %g" a
    | Decay (a, k)     -> Printf.sprintf "decay (%g, %g)" a k
    | Exp_decay (a, k) -> Printf.sprintf "exp_decay (%g, %g)" a k
    | RMSprop (a, k)   -> Printf.sprintf "rmsprop (%g, %g)" a k
    | Schedule a       -> Printf.sprintf "schedule %i" (Array.length a)

end


module Batch = struct

  type typ =
    | Fullbatch
    | Minibatch of int
    | Stochastic

  let run typ x y = match typ with
    | Fullbatch   -> x, y
    | Minibatch c -> let x, y, _ = Mat.draw_rows2 ~replacement:false x y c in x, y
    | Stochastic  -> let x, y, _ = Mat.draw_rows2 ~replacement:false x y 1 in x, y

  let batches typ x = match typ with
    | Fullbatch   -> 1
    | Minibatch c -> Mat.row_num x / c
    | Stochastic  -> Mat.row_num x

  let to_string = function
    | Fullbatch   -> "full"
    | Minibatch c -> Printf.sprintf "mini of %i" c
    | Stochastic  -> "stochastic"

end


module Loss = struct

  type typ =
    | L1norm
    | L2norm
    | Quadratic
    | Cross_entropy

  let run typ y y' = match typ with
    | L1norm        -> Maths.(l1norm (y - y'))
    | L2norm        -> Maths.(l2norm (y - y'))
    | Quadratic     -> Maths.(l2norm_sqr (y - y'))
    | Cross_entropy -> Maths.(cross_entropy y y')

  let to_string = function
    | L1norm        -> "l1norm"
    | L2norm        -> "l2norm"
    | Quadratic     -> "quadratic"
    | Cross_entropy -> "cross_entropy"

end


module Gradient = struct

  type typ =
    | GD          (* classic gradient descendent *)
    | CG          (* Hestenes and Stiefel 1952 *)
    | CD          (* Fletcher 1987 *)
    | NonlinearCG (* Fletcher and Reeves 1964 *)
    | DaiYuanCG   (* Dai and Yuan 1999 *)
    | NewtonCG    (* Newton conjugate gradient *)
    | Newton      (* Exact Newton *)

  (* FIXME *)
  let run = function
    | GD          -> fun _ _ _ g' -> Maths.neg g'
    | CG          -> fun _ g p g' -> (
        let y = Maths.(g' - g) in
        let b = Maths.((g' $@ y) / (p $@ y)) in
        Maths.(neg g' + (b $@ p))
      )
    | CD          -> fun _ g p g' -> (
        let b = Maths.(l2norm_sqr g' / (neg p $@ g)) in
        Maths.(neg g' + b $@ p)
      )
    | NonlinearCG -> fun _ g p g' -> (
        let b = Maths.((l2norm_sqr g') / (l2norm_sqr g)) in
        Maths.(neg g' + (b $@ p))
      )
    | DaiYuanCG   -> fun w g p g' -> (
        let y = Maths.(g' - g) in
        let b = Maths.((l2norm_sqr g') / (p $@ y)) in
        Maths.(neg g' + (b $@ p))
      )
    | NewtonCG    -> fun w g p g' -> Maths.neg g' (* TODO *)
    | Newton      -> fun w g p g' -> Maths.neg g' (* TODO *)

  let to_string = function
    | GD          -> "gradient decscendent"
    | CG          -> "conjugate gradient"
    | CD          -> "conjugate descendent"
    | NonlinearCG -> "nonlinear conjugate gradient"
    | DaiYuanCG   -> "dai & yuan conjugate gradient"
    | NewtonCG    -> "newton conjugate gradient"
    | Newton      -> "newtown"

end


module Momentum = struct

  type typ =
    | Standard of float
    | Nesterov of float
    | None

  let run = function
    | Standard m -> fun u u' -> Maths.(F m * u + u')
    | Nesterov m -> fun u u' -> Maths.((F m * F m * u) + (F m + F 1.) * u')
    | None       -> fun _ u' -> u'

  let default = function
    | Standard _ -> Standard 0.9
    | Nesterov _ -> Nesterov 0.9
    | None       -> None

  let to_string = function
    | Standard m -> Printf.sprintf "standard %g" m
    | Nesterov m -> Printf.sprintf "nesterov %g" m
    | None       -> Printf.sprintf "none"

end


module Regularisation = struct

  type typ =
    | L1norm of float
    | L2norm of float
    | None

  let run typ x = match typ with
    | L1norm a -> Maths.(F a * l1norm x)
    | L2norm a -> Maths.(F a * l2norm x)
    | None     -> F 0.

  let to_string = function
    | L1norm a -> Printf.sprintf "l1norm (alpha = %g)" a
    | L2norm a -> Printf.sprintf "l2norm (alhpa = %g)" a
    | None     -> "none"

end


module Clipping = struct

  type typ = None

end


module Stopping = struct

  type typ =
    | Early
    | None

end


module Params = struct

  type typ = {
    mutable epochs          : int;
    mutable batch           : Batch.typ;
    mutable gradient        : Gradient.typ;
    mutable loss            : Loss.typ;
    mutable learning_rate   : Learning_Rate.typ;
    mutable regularisation  : Regularisation.typ;
    mutable momentum        : Momentum.typ;
  }

  let default () = {
    epochs         = 1;
    batch          = Batch.Minibatch 100;
    gradient       = Gradient.GD;
    loss           = Loss.Cross_entropy;
    learning_rate  = Learning_Rate.(default (Const 0.));
    regularisation = Regularisation.None;
    momentum       = Momentum.None;
  }

  let to_string p =
    Printf.sprintf "--- Training config\n" ^
    Printf.sprintf "    epochs         : %i\n" (p.epochs) ^
    Printf.sprintf "    batch          : %s\n" (Batch.to_string p.batch) ^
    Printf.sprintf "    method         : %s\n" (Gradient.to_string p.gradient) ^
    Printf.sprintf "    loss           : %s\n" (Loss.to_string p.loss) ^
    Printf.sprintf "    learning rate  : %s\n" (Learning_Rate.to_string p.learning_rate) ^
    Printf.sprintf "    regularisation : %s\n" (Regularisation.to_string p.regularisation) ^
    Printf.sprintf "    momentum       : %s\n" (Momentum.to_string p.momentum) ^
    "---"

end


(* helper functions *)

let _print_info e_i e_n b_i b_n l l' =
  let l, l' = unpack_flt l, unpack_flt l' in
  let d = l -. l' in
  let s = if d = 0. then "-" else if d < 0. then "▲" else "▼" in
  Log.info "%i/%i | B: %i/%i | L: %g[%s]"
  e_i e_n b_i b_n l' s

let _print_summary t = Printf.printf "--- Training summary\n    Duration: %g s\n" t


(* core training functions *)

let train params forward backward update x y =
  let open Params in
  print_endline (Params.to_string params);

  (* make alias functions *)
  let batch = Batch.run params.batch in
  let loss_fun = Loss.run params.loss in
  let grad_fun = Gradient.run params.gradient in
  let rate_fun = Learning_Rate.run params.learning_rate in
  let regl_fun = Regularisation.run params.regularisation in
  let momt_fun = Momentum.run params.momentum in
  let upch_fun = Learning_Rate.update_ch params.learning_rate in

  (* operations in one iteration *)
  let iterate () =
    let xt, yt = batch x y in
    let yt', ws = forward xt in
    let loss = Maths.(loss_fun yt yt') in
    (* take the average of the loss *)
    let loss = Maths.(loss / (F (Mat.row_num yt |> float_of_int))) in
    (* add regularisation term if necessary *)
    let reg = match params.regularisation <> Regularisation.None with
      | true  -> Owl_utils.aarr_fold (fun a w -> Maths.(a + regl_fun w)) (F 0.) ws
      | false -> F 0.
    in
    let loss = Maths.(loss + reg) in
    let ws, gs' = backward loss in
    loss |> primal', ws, gs' in

  (* first iteration to bootstrap the training *)
  let t0 = Unix.time () in
  let _loss, _ws, _gs = iterate () in
  update _ws;

  (* variables used for specific modules *)
  let gs = ref _gs in
  let ps = ref (Owl_utils.aarr_map Maths.neg _gs) in
  let us = ref (Owl_utils.aarr_map (fun _ -> F 0.) _gs) in
  let ch = ref (Owl_utils.aarr_map (fun a -> F 0.) _gs) in

  (* variables used in training process *)
  let batches = Batch.batches params.batch x in
  let loss = ref (Array.make (params.epochs * batches) (F 0.)) in
  let idx = ref 0 in

  (* iterate all batches in each epoch *)
  for i = 1 to params.epochs do
    for j = 1 to batches do
      let loss', ws, gs' = iterate () in
      (* print out the current state of training *)
      _print_info i params.epochs j batches !loss.(!idx) loss';
      (* calculate gradient updates *)
      let ps' = Owl_utils.aarr_map2i (
        fun k l w g' ->
          let g, p = !gs.(k).(l), !ps.(k).(l) in
          grad_fun w g p g'
        ) ws gs' in
      (* update gcache if necessary *)
      ch := upch_fun gs' !ch;
      (* adjust direction based on learning_rate *)
      let us' = Owl_utils.aarr_map3 (fun p' g' c ->
        Maths.(p' * rate_fun i g' c)
      ) ps' gs' !ch in
      (* adjust direction based on momentum *)
      let us' = match params.momentum <> Momentum.None with
        | true  -> Owl_utils.aarr_map2 momt_fun !us us'
        | false -> us'
      in
      (* update the weight *)
      let ws' = Owl_utils.aarr_map2 (fun w u -> Maths.(w + u)) ws us' in
      update ws';
      (* save historical data *)
      if params.momentum <> Momentum.None then us := us';
      gs := gs';
      ps := ps';
      !loss.(!idx) <- loss';
      idx := !idx + 1;
    done
  done;

  (* print training summary *)
  _print_summary (Unix.time () -. t0);
  (* return loss history *)
  Array.map unpack_flt !loss



(* ends here *)