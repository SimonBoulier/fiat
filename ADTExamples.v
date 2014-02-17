Require Import String Omega.
Require Import FunctionalExtensionality.
Require Export ADT ADTRefinement ADTCache.

Generalizable All Variables.
Set Implicit Arguments.

Section BinOpSpec.
  (** Specification for comparisions over a collection **)

  Definition multiset := nat -> nat.
  Definition add (s : multiset) (n : nat) : multiset
    := fun m => if eq_nat_dec n m
                then S (s m)
                else s m.

  Global Arguments add s n / m.

  (* Specification for adding an element *)
  Definition add_spec : mutatorMethodSpec multiset
    := fun m x m' => forall k, m' k = (add m x) k.

  Arguments add_spec m x m' / .

  Variable opSpec : nat -> nat -> Prop.
  Variable defaultSpec : nat -> Prop.

  (* Specification for calculating op. *)

  Definition bin_op_spec
  : observerMethodSpec multiset
    := fun m _ n => (defaultSpec n /\ forall n', m n' = 0) \/ (* Either the set is empty *)
                    (m n > 0 /\ forall n', m n' > 0 -> opSpec n n'). (* Or n is the op-est thing in the set *)

  Arguments bin_op_spec / .

  Definition NatBinOpSpec
  : ADT
    := pickImpl (fun _ : unit => add_spec)
                (fun _ : unit => bin_op_spec).

End BinOpSpec.

Definition NatLower : ADT
  := NatBinOpSpec le (fun n => True).  (* Spec for collection with lower bound. *)

Definition NatUpper
: ADT := NatBinOpSpec ge (fun n => True).  (* Spec for collection with upper bound. *)

Section BinOpImpl.
  (* Implementation of comparisions over a collection implemented as a list. *)

  Require Import List.

  Variable op : nat -> nat -> nat.
  Variable defaultValue : nat.

  Definition add_impl : mutatorMethodType (list nat)
    := fun m x => ret (x :: m).

  Arguments add_impl / .

  Definition bin_op_impl : observerMethodType (list nat)
    := fun m _ => ret (match m with
                    | [] => defaultValue  (* Only return default if collection is empty *)
                    | a :: m' => (fold_left op m' a)
                  end).

  Arguments bin_op_impl / .

  Program Definition NatBinOpImpl
  : ADT
    := {| Rep := list nat;
          RepInv m := True;
          MutatorIndex := unit;
          ObserverIndex := unit;
          MutatorMethods := fun _ => add_impl;
          ObserverMethods := fun _ => bin_op_impl
       |}.

End BinOpImpl.

Section BinOpRefine.

  Variable opSpec : nat -> nat -> Prop.
  Variable defaultSpec : nat -> Prop.

  Variable op : nat -> nat -> nat.
  Variable defaultValue : nat.

  Hypothesis op_commutes : forall x y, op x y = op y x.
  Hypothesis op_assoc : forall x y z, op (op x y) z = op x (op y z).
  Hypothesis default_satisfies_defaultSpec : defaultSpec defaultValue.
  Hypothesis op_returns_arg : forall n m,
    op n m = n \/ op n m = m.
  Hypothesis op_preserves_op1 : forall n m,
    opSpec (op n m) m.
  Hypothesis op_preserves_op2 : forall n m,
    opSpec (op n m) n.
  Hypothesis op_refl : Reflexive opSpec.
  Hypothesis op_trans : Transitive opSpec.

  Lemma fold_left_op_preserves_opSpec l :
    forall a n', opSpec a n' -> opSpec (fold_left op l a) n'.
  Proof.
    induction l; simpl; auto.
    intros; eapply IHl; etransitivity; [ | eassumption]; eauto.
  Qed.

  Hint Resolve fold_left_op_preserves_opSpec.

  Lemma fold_left_op_preserves_opSpec' l
    : forall acc,
      opSpec (fold_left op l acc) acc.
  Proof.
    eauto.
  Qed.

  Hint Resolve fold_left_op_preserves_opSpec'.

  Lemma fold_left_op_In_preserves_opSpec :
    forall m n' a,
      In n' m -> opSpec (fold_left op m a) n'.
  Proof.
    induction m; simpl; intuition; subst.
    destruct (op_returns_arg a0 n'); rewrite H; eauto.
    generalize (op_preserves_op1 a0 n'); rewrite H; eauto.
  Qed.

  Hint Resolve fold_left_op_In_preserves_opSpec.

  Lemma fold_left_discards_less_oppy :
    forall m a, a <> fold_left op m a -> exists a', In (fold_left op m a) m /\ op a a' = a'.
  Proof.
    induction m; simpl; intuition.
    destruct (op_returns_arg a0 a); rewrite H0 in *|-*; eauto.
    destruct (IHm _ H) as [a' [In_a' op_a] ]; eauto.
    destruct (eq_nat_dec a (fold_left op m a)); eauto.
    destruct (IHm _ n); exists x; intuition.
    rewrite <- H3, <- op_assoc, H0; auto.
  Qed.

  Lemma fold_left_constains_more_oppy :
    forall m a, a <> fold_left op m a -> count_occ eq_nat_dec m (fold_left op m a) > 0.
  Proof.
    intros m a neq; destruct (fold_left_discards_less_oppy m neq) as [a' [In_a' op_a] ].
    eapply count_occ_In; eauto.
  Qed.

  Hint Resolve fold_left_constains_more_oppy.

  Program Definition absList2Multiset (l : list nat) : multiset := count_occ eq_nat_dec l.

  Arguments absList2Multiset l / n .
  Arguments add_spec m x m' /.

  Theorem refine_add_impl m n :
  refine {m' : list nat |
          add_spec (absList2Multiset m) n (absList2Multiset m')}
         (add_impl m n).
  Proof.
    unfold refine; intros; apply_in_hyp computes_to_inv; simpl in *;
    subst; constructor; auto.
  Qed.

  Hint Resolve refine_add_impl.

  Arguments bin_op_spec opSpec defaultSpec m x n /.

  Theorem refine_bin_op_impl m n :
  refine {m' : nat |
          bin_op_spec opSpec defaultSpec (absList2Multiset m) n m'}
         (bin_op_impl op defaultValue m n).
  Proof.
    intros v old_hyp.
    apply computes_to_inv in old_hyp; simpl in old_hyp; subst.
    constructor; simpl; auto.
    destruct m; subst; intuition.
    right; revert n0; induction m; simpl; [intuition; (find_if_inside; substs; intuition) | intuition].
    - repeat (find_if_inside; substs; intuition).
      destruct (op_returns_arg n0 a); rewrite H in *|-*; eauto.
    - repeat find_if_inside; substs; eauto;
      destruct (op_returns_arg n0 a); rewrite H0 in *|-*; eauto.
      destruct (IHm n0) as [_ IHm']; specialize (IHm' n'); simpl in IHm';
      find_if_inside; intuition.
      destruct (IHm a) as [_ IHm']; specialize (IHm' n'); simpl in IHm';
      find_if_inside; intuition.
  Qed.

  Lemma refines_NatBinOp
  : refineADT (NatBinOpSpec opSpec defaultSpec) (NatBinOpImpl op defaultValue).
  Proof.
    unfold NatBinOpSpec.
    rewrite (refines_rep_pickImpl absList2Multiset).
    econstructor 1 with (abs := @Return (list nat))
                          (mutatorMap := @id unit)
                          (observerMap := @id unit); simpl; intros.
    interleave_autorewrite_refine_monad_with ltac:(apply refine_add_impl).
    interleave_autorewrite_refine_monad_with ltac:(apply refine_bin_op_impl).
    auto.
  Qed.

End BinOpRefine.

Section ImplExamples.

  Local Ltac induction_list_then tac :=
    lazymatch goal with
  | [ l : list _ |- _ ]
    => repeat match goal with
                | [ H : appcontext[l] |- _ ] => clear H
              end;
      induction l; tac
  end.

  Local Ltac manipulate_op op_assoc op_comm :=
    match goal with
      | _ => reflexivity
      | _ => progress simpl in *
      | _ => apply op_comm
      | _ => rewrite <- ?op_assoc; revert op_assoc op_comm; rewrite_hyp'; intros
      | _ => rewrite ?op_assoc; revert op_assoc op_comm; rewrite_hyp'; intros
      | _ => rewrite <- ?op_assoc; f_equal; []
      | _ => rewrite ?op_assoc; f_equal; []
      | _ => apply op_comm
    end.

  Local Ltac deep_manipulate_op op op_assoc op_comm can_comm_tac :=
    repeat match goal with
             | _ => progress repeat manipulate_op op_assoc op_comm
             | [ |- appcontext[op ?a ?b] ]
               => can_comm_tac a b;
                 rewrite (op_comm a b);
                 let new_can_comm_tac :=
                     fun x y =>
                       can_comm_tac x y;
                       try (unify x a;
                            unify y b;
                            fail 1 "Cannot commute" a "and" b "again")
                 in deep_manipulate_op op op_assoc op_comm new_can_comm_tac
           end.

  Local Ltac solve_after_induction_list op op_assoc op_comm :=
    solve [ deep_manipulate_op op op_assoc op_comm ltac:(fun a b => idtac) ].

  Local Ltac t :=
    repeat match goal with
             | _ => assumption
             | _ => intro
             | _ => progress simpl in *
             | [ |- appcontext[if string_dec ?A ?B then _ else _ ] ]
               => destruct (string_dec A B)
             | _ => progress subst
             | [ H : ex _ |- _ ] => destruct H
             | [ H : and _ _ |- _ ] => destruct H
             | _ => split
             | [ H : option _ |- _ ] => destruct H
             | [ H : _ |- _ ] => solve [ inversion H ]
             | [ |- appcontext[match ?x with _ => _ end] ] => destruct x
             | [ H : appcontext[match ?x with _ => _ end] |- _  ] => destruct x
             | [ H : Some _ = Some _ |- _ ] => inversion H; clear H
             | _ => progress f_equal; []
             | _ => progress intuition
             | _ => repeat esplit; reflexivity
             | [ H : _ |- _ ] => rewrite H; try (rewrite H; fail 1)
           end.

  Local Ltac t' op op_assoc op_comm :=
    repeat first [ progress t
                 | progress induction_list_then ltac:(solve_after_induction_list op op_assoc op_comm) ].

  Require Import Min.

  Lemma min_trans : forall n m v,
                      n <= v
                      -> min n m <= v.
    intros; destruct (min_spec n m); omega.
  Qed.

  Hint Resolve min_trans.
  Hint Resolve min_comm.

  Lemma ObserverIndexUnit_eq : forall idx idx' : (),
                                 {idx = idx'} + {idx <> idx'}.
  Proof.
    decide equality.
  Defined.
  Hint Resolve ObserverIndexUnit_eq.

  Arguments NatLower / .

  Definition MinCollection (defaultValue : nat) :
    { Rep : ADT
    | refineADT NatLower Rep }.
  Proof.
    eexists.
    apply refines_NatBinOp with
             (op := min)
               (defaultValue := defaultValue); auto with arith typeclass_instances.
    + intros; rewrite min_assoc; auto.
    + intros; edestruct min_dec; eauto.
  Defined.

  Arguments NatLower / .
  Arguments NatBinOpSpec / .
  Arguments pickImpl / .

  (* Still need to clean this proof up to make it readable.
             More notation, better tactic support. *)

  Lemma min_assoc
  : forall x y z : nat, min (min x y) z = min x (min y z).
  Proof.
    intros; rewrite min_assoc; eauto.
  Qed.
  Hint Resolve min_assoc.

  Lemma min_returns_arg
  : forall n0 m : nat, min n0 m = n0 \/ min n0 m = m.
  Proof.
    intros; edestruct min_dec; eauto.
  Qed.
  Hint Resolve min_returns_arg.

  Lemma min_preserves_le
  : forall n m : nat, min n m <= m.
  Proof.
    intros; destruct (min_dec n m); eauto with arith.
  Qed.
  Hint Resolve min_preserves_le.

  Definition MinCollectionCached (defaultValue : nat) :
    Sharpened NatLower.
  Proof.
    (* Step 1: Update the representation. *)
    hone representation using (fun x => ret (absList2Multiset x)).
    (* Step 2: Update the mutator. *)
    hone mutator () using add_impl.
    { (* Proof that add_impl refines add_spec. *)
      rewrite <- refine_add_impl.
      intros v computes_to_v; inversion_by computes_to_inv;
      repeat econstructor; inversion_by computes_to_inv; subst; eauto.
    }
    simpl. (* Need to get rid of this simpl. *)
    (* Step 3: Add the Cache and replace observer. *)
    cache observer using spec (fun r => bin_op_spec le (fun _ => True) (absList2Multiset r) defaultValue).
    { (* Proof that the cached value [cachedVal] is a refinement of the minimum observer. *)
      intros; autorewrite with refine_monad; unfold bin_op_spec in *;
      intuition;
      intros v' old_hyp; inversion_by computes_to_inv; subst; constructor; intuition;
      intros v' old_hyp; inversion_by computes_to_inv; subst; constructor;
        intuition.
    }
    simpl. (* Need to get rid of this simpl too. *)
    (* Step 5: Replace the [Pick] used to get [cachedVal] in the add implementation. *)
    hone mutator ().
    {
      (* Implementation of the cache for the [add] mutator. *)
      subst; find_if_inside; try congruence.
      unfold add_impl; simpl; intros; autorewrite with refine_monad; unfold add_impl; simpl.
      rewrite (refine_bin_op_impl (opSpec := le)) with (defaultValue := defaultValue)
      (m := n :: origRep new_state); eauto with typeclass_instances.
    }
    (* Done with the refinements :)*)
    simpl; finish sharpening.
  Defined.

  Fixpoint BuildList n :=
    match n with
      | 0 => []
      | S n' => n' :: BuildList n'
    end.

  Definition MinCollectionADT :=
    ObserverMethods (proj1_sig (MinCollection 7000)) () (BuildList 2000) 11.
  Definition MinCollectionCachedADT :=
    ObserverMethods (proj1_sig (MinCollectionCached 7000)) ()
                   {| origRep := BuildList 2000;
                      cachedVal := 0 |} 11.

  Time Eval compute in MinCollectionCachedADT.
  Time Eval compute in MinCollectionADT.

  Require Import Max.

  Lemma max_trans : forall n m v,
                      n >= v
                      -> max n m >= v.
    intros; destruct (max_spec n m); omega.
  Qed.

  Hint Resolve max_trans.

  Definition MaxCollection (defaultValue : nat) :
    { Rep : ADT
    | refineADT NatUpper Rep }.
  Proof.
    eexists; eapply refines_NatBinOp with
             (op := max)
               (defaultValue := defaultValue); t.
    rewrite max_assoc; auto.
    edestruct max_dec; eauto.
  Defined.

End ImplExamples.




(* Definition NatLower : ADT  *)
(*   := NatBinOpSpec le (fun n => n = 0).  (* Spec for collection with lower bound. *) *)

(* Definition NatUpper  *)
(* : ADT := NatBinOpSpec ge (fun n => n = 0).  (* Spec for collection with upper bound. *) *)


(* Definition NatLowerI defaultValue : ADT (NatLower defaultValue) *)
(*   := NatBinOpI _ _ _ _. *)

(* Definition NatUpperI : ADTimpl (NatUpper default_val) *)
(*   := NatBinOpI _ _ _ _. *)

(*   Program Definition NatUpper default_value : ADT *)
(*     := NatBinOpSpec max default_value. *)

(*   Program Definition NatSum default_value : ADT *)
(*     := NatBinOpSpec plus default_value. *)

(*   Program Definition NatProd default_value : ADT *)
(*     := NatBinOpSpec mult default_value. *)

(*   Hint Immediate le_min_l le_min_r le_max_l le_max_r. *)

(*   Lemma min_trans : forall n m v, *)
(*                       n <= v *)
(*                       -> min n m <= v. *)
(*     intros; destruct (min_spec n m); omega. *)
(*   Qed. *)

(*   Lemma max_trans : forall n m v, *)
(*                       n >= v *)
(*                       -> max n m >= v. *)
(*     intros; destruct (max_spec n m); omega. *)
(*   Qed. *)

(*   Hint Resolve min_trans max_trans. *)

(*   Arguments add _ _ _ / . *)


(*   Section def_NatBinOpI. *)

(*     Local Ltac induction_list_then tac := *)
(*       lazymatch goal with *)
(*   | [ l : list _ |- _ ] *)
(*     => repeat match goal with *)
(*                 | [ H : appcontext[l] |- _ ] => clear H *)
(*               end; *)
(*       induction l; tac *)
(*     end. *)

(*     Local Ltac manipulate_op op_assoc op_comm := *)
(*       match goal with *)
(*         | _ => reflexivity *)
(*         | _ => progress simpl in * *)
(*         | _ => apply op_comm *)
(*         | _ => rewrite <- ?op_assoc; revert op_assoc op_comm; rewrite_hyp'; intros *)
(*         | _ => rewrite ?op_assoc; revert op_assoc op_comm; rewrite_hyp'; intros *)
(*         | _ => rewrite <- ?op_assoc; f_equal; [] *)
(*         | _ => rewrite ?op_assoc; f_equal; [] *)
(*         | _ => apply op_comm *)
(*       end. *)

(*     Local Ltac deep_manipulate_op op op_assoc op_comm can_comm_tac := *)
(*       repeat match goal with *)
(*                | _ => progress repeat manipulate_op op_assoc op_comm *)
(*                | [ |- appcontext[op ?a ?b] ] *)
(*                  => can_comm_tac a b; *)
(*                    rewrite (op_comm a b); *)
(*                    let new_can_comm_tac := *)
(*                        fun x y => *)
(*                          can_comm_tac x y; *)
(*                          try (unify x a; *)
(*                               unify y b; *)
(*                               fail 1 "Cannot commute" a "and" b "again") *)
(*                    in deep_manipulate_op op op_assoc op_comm new_can_comm_tac *)
(*              end. *)

(*     Local Ltac solve_after_induction_list op op_assoc op_comm := *)
(*       solve [ deep_manipulate_op op op_assoc op_comm ltac:(fun a b => idtac) ]. *)

(*     Local Ltac t := *)
(*       repeat match goal with *)
(*                | _ => assumption *)
(*                | _ => intro *)
(*                | _ => progress simpl in * *)
(*                | [ |- appcontext[if string_dec ?A ?B then _ else _ ] ] *)
(*                  => destruct (string_dec A B) *)
(*                | _ => progress subst *)
(*                | [ H : ex _ |- _ ] => destruct H *)
(*                | [ H : and _ _ |- _ ] => destruct H *)
(*                | _ => split *)
(*                | [ H : option _ |- _ ] => destruct H *)
(*                | [ H : _ |- _ ] => solve [ inversion H ] *)
(*                | [ |- appcontext[match ?x with _ => _ end] ] => destruct x *)
(*                | [ H : appcontext[match ?x with _ => _ end] |- _  ] => destruct x *)
(*                | [ H : Some _ = Some _ |- _ ] => inversion H; clear H *)
(*                | _ => progress f_equal; [] *)
(*                | _ => progress intuition *)
(*                | _ => repeat esplit; reflexivity *)
(*                | [ H : _ |- _ ] => rewrite H; try (rewrite H; fail 1) *)
(*              end. *)

(*     Local Ltac t' op op_assoc op_comm := *)
(*       repeat first [ progress t *)
(*                    | progress induction_list_then ltac:(solve_after_induction_list op op_assoc op_comm) ]. *)

(*     Definition NatBinOpImpl *)
(*                (op : nat -> nat -> nat) *)
(*                (default_value : nat) : ADT. *)
(*     Proof. *)
(*       intros. *)
(*       refine {|  *)
(*           Model := option nat; *)
(*           MutatorIndex := unit; *)
(*           ObserverIndex := unit; *)
(*           MutatorMethods u val x := ret (match val with  *)
(*                                              | None => Some x *)
(*                                              | Some x' => Some (op x x') *)
(*                                          end)%comp; *)
(*           ObserverMethods u val x := ret (match val with  *)
(*                                               | None => default_value *)
(*                                               | Some x => x *)
(*                                           end) *)
(*         |}. *)
(*     Defined. *)

(*   End def_NatBinOpI. *)

(*       Print ADT. *)
(*       intros []. *)

(*       refine {| *)
(*           Model := option (nat * nat); *)
(*           MutatorMethods u val x := (ret (match val with *)
(*                                                  | None => Some x *)
(*                                                  | Some x' => Some (op x (fst x')) *)
(*                                                end, *)
(*                                                0))%comp; *)
(*           ObserverMethods u val x := (ret (val, *)
(*                                                 match val with *)
(*                                                   | None => default_value *)
(*                                                   | Some x => x *)
(*                                                 end))%comp *)
(*         |}; *)
(*         intros []; *)
(*         solve [ (intros m [n|] [l [H0 H1] ] x ? ?); *)
(*                 inversion_by computes_to_inv; subst; simpl in *; *)
(*                 (exists (add m x)); *)
(*                 repeat split; *)
(*                 try (exists (x::l)); *)
(*                 abstract t' op op_assoc op_comm *)
(*               | intros m [n|] [l [H0 H1] ] x ? ?; *)
(*                        inversion_by computes_to_inv; subst; simpl in *; *)
(*                 repeat (split || exists m || exists l); *)
(*                 abstract t' op op_assoc op_comm *)
(*               | intros m [n|] [l [H0 H1] ] x ? ?; *)
(*                        inversion_by computes_to_inv; subst; simpl in *; *)
(*                 [ repeat split; *)
(*                   try (exists (add (fun _ => 0) n)); *)
(*                   repeat split; *)
(*                   try (exists (n::nil)); *)
(*                   abstract (repeat split) *)
(*                 | repeat split; *)
(*                   try (exists m); *)
(*                   repeat split; *)
(*                   try (exists l); *)
(*                   abstract (repeat split; assumption) ] *)
(*               ]. *)
(*     Defined. *)
(*   End def_NatBinOpI. *)

(*   Section nat_op_ex. *)
(*     Variable default_val : nat. *)

(*     Definition NatLowerI : ADTimpl (NatLower default_val) *)
(*       := NatBinOpI _ _ _ _. *)

(*     Definition NatUpperI : ADTimpl (NatUpper default_val) *)
(*       := NatBinOpI _ _ _ _. *)

(*     Definition NatSumI : ADTimpl (NatSum default_val) *)
(*       := NatBinOpI _ _ _ _. *)

(*     Definition NatProdI : ADTimpl (NatProd default_val) *)
(*       := NatBinOpI _ _ _ _. *)
(*   End nat_op_ex. *)

(*   Local Open Scope string_scope. *)

(*   Definition NatSumProd_spec : ADT *)
(*     := {| Model := multiset; *)
(*           MutatorIndex := unit; *)
(*           ObserverIndex := unit + unit; *)
(*           MutatorMethodSpecs u := add_spec; *)
(*           ObserverMethodSpecs u m x n := *)
(*             match u with *)
(*               | inl _ => bin_op_spec plus 0 m x n *)
(*               | inr _ => bin_op_spec mult 1 m x n *)
(*             end *)
(*        |}. *)
