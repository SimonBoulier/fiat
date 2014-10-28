Ltac rnm a b :=
  rename a into b.

Require Import Cito.facade.Facade.
Require Import AutoDB.

Unset Implicit Arguments.

Import StringMap.StringMap.

Lemma Some_inj : forall A (x y: A),
                   Some x = Some y -> x = y.
  intros ** H; injection H; trivial.
Qed.

Lemma MapsTo_unique :
  forall {A} map key (v1 v2: A),
    MapsTo key v1 map ->  
    MapsTo key v2 map ->  
    v1 = v2.
Proof.
  intros.
  rewrite StringMapFacts.find_mapsto_iff in *.
  apply Some_inj; rewrite <- H, <- H0; trivial.
Qed.

Lemma SCA_inj :
  forall av v v',
    SCA av v = SCA av v' -> v = v'.
Proof.
  intros ** H; injection H; trivial.
Qed.

Definition cond_respects_MapEq {elt} :=
  Proper (StringMapFacts.M.Equal (elt := elt) ==> iff).

Definition WZero := (Word.wzero 32).
Definition WOne  := (Word.wone  32).

Definition BoolToW (b: bool) := if b then WOne else WZero.

Definition WToBool (w: @Word.word 32) := negb (Word.weqb w WZero).

Lemma BoolToW_invert : forall b, WToBool (BoolToW b) = b.
Proof.
  destruct b; intuition.
Qed.

Definition empty_env ADTValue : Env ADTValue := {| Label2Word := fun _ => None; Word2Spec := fun _ => None |}.

Definition empty_state ADTValue : State ADTValue := StringMapFacts.M.empty (Value ADTValue).

Lemma eval_binop_inv :
  forall (test: bool),
    IL.wneb (eval_binop (inr IL.Eq) (if test then WOne else WZero) WZero)
            (Word.natToWord 32 0) = negb test.
Proof.
  intros; destruct test; simpl; reflexivity.
Qed.
Opaque WOne WZero.

Ltac autospecialize :=
  repeat match goal with 
           | [ H: forall a b, ?x a -> ?y a b -> _, H': ?x _, H'': ?y _ _ |- _ ] => specialize (H _ _ H' H'') 
           | [ H: forall a b, ?x a /\ ?x' a -> ?y a b -> _, H'1: ?x _, H'2: ?x' _, H'': ?y _ _ |- _ ] => specialize (H _ _ (conj H'1 H'2) H'')
         end.

Lemma compile_if :
  forall { av env } testvar retvar (test: bool) (precond postcond: _ -> Prop) truecase falsecase,
  refine (Pick (fun prog => forall init_state final_state,
                              precond init_state ->
                              RunsTo env prog init_state final_state ->
                              (MapsTo retvar (SCA av (if test then truecase else falsecase)) final_state 
                               /\ postcond final_state)))
         (Bind (Pick (fun progtest => forall init_state inter_state,
                                        precond init_state ->
                                        RunsTo env progtest init_state inter_state ->
                                        (MapsTo testvar (SCA av (BoolToW test)) inter_state /\
                                         precond inter_state)))
               (fun ptest => 
                  (Bind (Pick (fun prog1 => forall inter_state final_state,
                                              (test = true /\ 
                                               precond inter_state /\ 
                                               MapsTo testvar (SCA av (BoolToW test)) inter_state) ->
                                              RunsTo env prog1 inter_state final_state ->
                                              (MapsTo retvar (SCA av truecase) final_state /\
                                               postcond final_state)))
                        (fun p1 => 
                           Bind 
                             (Pick (fun prog2 => 
                                      forall inter_state final_state,
                                        (test = false /\ 
                                         precond inter_state /\ 
                                         MapsTo testvar (SCA av (BoolToW test)) inter_state) ->
                                        RunsTo env prog2 inter_state final_state ->
                                        (MapsTo retvar (SCA av falsecase) final_state /\
                                         postcond final_state)))
                             (fun p2 => ret (Seq ptest
                                                 (Facade.If (SyntaxExpr.TestE IL.Eq
                                                                              (SyntaxExpr.Var testvar) 
                                                                              (SyntaxExpr.Const WZero))
                                                            (p2)
                                                            (p1)))))))).                
Proof.
  unfold refine. 
  intros av env testvar retvar test precond postcond truecase falsecase ** .
  inversion_by computes_to_inv.
  rnm x ptest.
  rnm x0 ptrue.
  rnm x1 pfalse.
  rnm H pfalse_retval.
  rnm H4 pfalse_postcond.
  rnm H2 ptrue_retval.
  rnm H5 ptrue_postcond.
  rnm H1 ptest_testvar.
  rnm H6 ptest_precond.

  constructor. intros ? ? init_state_consistent v_runs.
  subst.

  inversion_clear v_runs; subst.
  inversion_clear H0; subst;
  unfold is_true, is_false, eval_bool, eval, eval_binop_m in H1;
    rnm st' inter_state;
    (destruct (find (elt:=Value av) testvar inter_state) as [ v | ] eqn:testvar_correct; try congruence);
    (destruct v as [ testw | ]; try congruence);
    apply Some_inj in H1;
  specialize (ptest_testvar init_state inter_state init_state_consistent H);
  rewrite <- StringMapFacts.find_mapsto_iff in *;
  pose proof (MapsTo_unique _ _ _ _ ptest_testvar testvar_correct) as Heq; apply SCA_inj in Heq; subst; clear testvar_correct;
  unfold BoolToW in H1;
  rewrite eval_binop_inv, ?negb_true_iff, ?negb_false_iff in H1; subst;
  specialize (ptest_precond init_state inter_state init_state_consistent H).

  (* TODO extend autospecialize to deal with this *)
  specialize (pfalse_retval inter_state final_state (conj (@eq_refl _ _) (conj ptest_precond ptest_testvar)) H2).
  specialize (pfalse_postcond inter_state final_state (conj (@eq_refl _ _) (conj ptest_precond ptest_testvar)) H2).
  intuition.

  specialize (ptrue_retval inter_state final_state (conj (@eq_refl _ _) (conj ptest_precond ptest_testvar)) H2).
  specialize (ptrue_postcond inter_state final_state (conj (@eq_refl _ _) (conj ptest_precond ptest_testvar)) H2).
  intuition.
Qed.

Lemma compile_binop :
  forall op,
  forall retvar temp1 temp2,
  forall av env,
  forall (precond postcond: State _ -> Prop),
  forall w1 w2,
    cond_respects_MapEq postcond ->
    (forall x state, postcond state -> postcond (add retvar x state)) ->
    refine (Pick (fun prog => forall init_state final_state,
                                precond init_state ->
                                RunsTo env prog init_state final_state ->
                                (MapsTo retvar (SCA av ((IL.evalBinop op) w1 w2)) final_state 
                                 /\ postcond final_state)))
           (Bind (Pick (fun prog1 => forall init_state inter_state,
                                       precond init_state ->
                                       RunsTo env prog1 init_state inter_state ->
                                       (MapsTo temp1 (SCA av w1) inter_state
                                        /\ precond inter_state)))
                 (fun p1 => 
                    Bind 
                      (Pick (fun prog2 => 
                               forall inter_state final_state,
                                 precond inter_state /\ MapsTo temp1 (SCA av w1) inter_state ->
                                 RunsTo env prog2 inter_state final_state ->
                                 (MapsTo temp2 (SCA av w2) final_state 
                                  /\ MapsTo temp1 (SCA av w1) final_state
                                  /\ postcond final_state)))
                      (fun p2 => ret (Seq p1 
                                          (Seq p2 
                                               (Assign retvar 
                                                       (SyntaxExpr.Binop 
                                                          op
                                                          (SyntaxExpr.Var temp1) 
                                                          (SyntaxExpr.Var temp2)))))))).
  unfold refine; simpl.
  intros op retvar temp1 temp2 av env precond postcond w1 w2 postcond_meaningful postcond_indep_retvar ** .
  inversion_by computes_to_inv.
  rnm x prog1.
  rnm x0 prog2.
  rnm H prog2_returns_w2.
  rnm H3 prog1_returns_w1.
  rnm H5 prog1_consistent.
  rnm H1 prog2_consistent.
  rnm H4 prog2_ensures_postcond.
  constructor; intros.
  rnm H init_state_consistent.
  subst.
  inversion H0; subst; clear H0.
  inversion H5; subst; clear H5.
  rnm st' post_prog1_state.
  rnm st'0 post_prog2_state.
   
  
  autospecialize.
  clear H2.
  clear H1.

  inversion_clear H6.

  unfold cond_respects_MapEq in postcond_meaningful.
  rewrite H0; clear H0.

  unfold eval in H; simpl in H;
  unfold eval_binop_m in H; simpl in H.

  set (find temp1 _) as r1 in H.
  set (find temp2 _) as r2 in H.
  destruct r1 eqn:eq1; subst; try congruence.
  destruct v; try congruence.
  destruct r2 eqn:eq2; subst; try congruence.
  destruct v; try congruence.

  rewrite StringMapFacts.find_mapsto_iff in *.
(*  rewrite <- prog2_consistent in *. 
  rewrite <- prog1_returns_w1 in *; clear prog1_returns_w1. *)
  rewrite <- StringMapFacts.find_mapsto_iff in *.
  subst.

  inversion_clear H.

  pose proof (MapsTo_unique _ _ _ _ eq1 prog2_consistent); apply SCA_inj in H; subst; clear eq1; clear prog1_returns_w1.
  pose proof (MapsTo_unique _ _ _ _ eq2 prog2_returns_w2); apply SCA_inj in H; subst; clear eq2; clear prog2_returns_w2.

  split.

  apply StringMapFacts.M.add_1; reflexivity.
  apply postcond_indep_retvar; eauto.
Qed.

Lemma compile_test : (* Exactly the same proof as compile_binop *)
  forall op,
  forall retvar temp1 temp2,
  forall av env,
  forall (precond postcond: State _ -> Prop),
  forall w1 w2,
    cond_respects_MapEq postcond ->
    (forall x state, postcond state -> postcond (add retvar x state)) ->
    refine (Pick (fun prog => forall init_state final_state,
                                precond init_state ->
                                RunsTo env prog init_state final_state ->
                                (MapsTo retvar (SCA av (BoolToW ((IL.evalTest op) w1 w2))) final_state 
                                 /\ postcond final_state)))
           (Bind (Pick (fun prog1 => forall init_state inter_state,
                                       precond init_state ->
                                       RunsTo env prog1 init_state inter_state ->
                                       (MapsTo temp1 (SCA av w1) inter_state
                                        /\ precond inter_state)))
                 (fun p1 => 
                    Bind 
                      (Pick (fun prog2 => 
                               forall inter_state final_state,
                                 precond inter_state /\ MapsTo temp1 (SCA av w1) inter_state ->
                                 RunsTo env prog2 inter_state final_state ->
                                 (MapsTo temp2 (SCA av w2) final_state 
                                  /\ MapsTo temp1 (SCA av w1) final_state
                                  /\ postcond final_state)))
                      (fun p2 => ret (Seq p1 
                                          (Seq p2 
                                               (Assign retvar 
                                                       (SyntaxExpr.TestE 
                                                          op
                                                          (SyntaxExpr.Var temp1) 
                                                          (SyntaxExpr.Var temp2)))))))).
  unfold refine; simpl.
  intros op retvar temp1 temp2 av env precond postcond w1 w2 postcond_meaningful postcond_indep_retvar ** .
  inversion_by computes_to_inv.
  rnm x prog1.
  rnm x0 prog2.
  rnm H prog2_returns_w2.
  rnm H3 prog1_returns_w1.
  rnm H5 prog1_consistent.
  rnm H1 prog2_consistent.
  rnm H4 prog2_ensures_postcond.
  constructor; intros.
  rnm H init_state_consistent.
  subst.
  inversion H0; subst; clear H0.
  inversion H5; subst; clear H5.
  rnm st' post_prog1_state.
  rnm st'0 post_prog2_state.

  autospecialize.
  clear H2.
  clear H1.

  inversion_clear H6.

  unfold cond_respects_MapEq in postcond_meaningful.
  rewrite H0; clear H0.

  unfold eval in H; simpl in H;
  unfold eval_binop_m in H; simpl in H.

  set (find temp1 _) as r1 in H.
  set (find temp2 _) as r2 in H.
  destruct r1 eqn:eq1; subst; try congruence.
  destruct v; try congruence.
  destruct r2 eqn:eq2; subst; try congruence.
  destruct v; try congruence.

  rewrite StringMapFacts.find_mapsto_iff in *.
(*  rewrite <- prog2_consistent in *. 
  rewrite <- prog1_returns_w1 in *; clear prog1_returns_w1. *)
  rewrite <- StringMapFacts.find_mapsto_iff in *.
  subst.

  inversion_clear H.

  pose proof (MapsTo_unique _ _ _ _ eq1 prog2_consistent); apply SCA_inj in H; subst; clear eq1; clear prog1_returns_w1.
  pose proof (MapsTo_unique _ _ _ _ eq2 prog2_returns_w2); apply SCA_inj in H; subst; clear eq2; clear prog2_returns_w2.

  split.

  apply StringMapFacts.M.add_1; reflexivity.
  apply postcond_indep_retvar; eauto.
Qed.

Lemma weaken_preconditions :
  forall av env (old_precond new_precond postcond: State av -> Prop), 
    (forall s, old_precond s -> new_precond s) ->
    refine
      (Pick (fun prog => 
               forall init_state final_state,
                 old_precond init_state ->
                 RunsTo env prog init_state final_state -> 
                 postcond final_state))
      (Pick (fun prog =>
               forall init_state final_state,
                 new_precond init_state ->
                 RunsTo env prog init_state final_state -> 
                 postcond final_state)).
Proof.
  unfold refine; intros; inversion_by computes_to_inv.
  constructor; intros; eapply H0; intuition. apply H; eassumption. eassumption.
Qed.

Lemma drop_preconditions :
  forall av env (precond postcond: State av -> Prop), 
    refine 
      (Pick (fun prog => 
               forall init_state final_state,
                 precond init_state ->
                 RunsTo env prog init_state final_state -> 
                 postcond final_state))
      (Pick (fun prog =>
               forall init_state final_state,
                 (fun _ => True) init_state ->
                 RunsTo env prog init_state final_state -> 
                 postcond final_state)).
Proof.
  eauto using weaken_preconditions.
Qed.

Lemma strengthen_postconditions :
  forall av env (precond old_postcond new_postcond: State av -> Prop), 
    (forall s, new_postcond s -> old_postcond s) ->
    refine
      (Pick (fun prog => 
               forall init_state final_state,
                 precond init_state ->
                 RunsTo env prog init_state final_state -> 
                 old_postcond final_state))
      (Pick (fun prog =>
               forall init_state final_state,
                 precond init_state ->
                 RunsTo env prog init_state final_state -> 
                 new_postcond final_state)).
Proof.
  unfold refine; intros; inversion_by computes_to_inv.
  constructor; intros; eapply H; intuition; eapply H0; eassumption. 
Qed.

Lemma start_compiling' ret_var : 
  forall {av env init_state} v,
    refine (ret v) 
           (Bind (Pick (fun prog => 
                          forall init_state final_state,
                            (fun x => True) init_state ->
                            RunsTo env prog init_state final_state -> 
                            MapsTo ret_var (SCA av v) final_state 
                            /\ (fun x => True) final_state))
                 (fun prog => 
                    Bind (Pick (fun final_state => RunsTo env prog init_state final_state))
                         (fun final_state => Pick (fun x => MapsTo ret_var (SCA av x) final_state)))).
  intros.
  unfold refine.
  intros.
  inversion_by computes_to_inv.
  apply eq_ret_compute.

  apply (H _ _ I) in H1.
  eapply SCA_inj.
  eapply MapsTo_unique; eauto.
Qed.

Definition start_compiling := fun ret_var av => @start_compiling' ret_var av (empty_env av) (empty_state av).

Ltac spam :=
  solve [ unfold cond_respects_MapEq, Proper, respectful; 
          first [
              setoid_rewrite StringMapFacts.find_mapsto_iff;
              intros; match goal with 
                          [ H: StringMapFacts.M.Equal _ _ |- _ ] => 
                          rewrite H in * 
                      end;
              intuition 
            | intuition; 
              first [
                  apply StringMapFacts.M.add_2; 
                  congruence
                | idtac ] ] ].

Lemma compile_constant :
  forall retvar av env,
  forall w1 (precond postcond: State av -> Prop), 
    cond_respects_MapEq postcond ->
    (forall x state, precond state -> 
                     postcond (add retvar x state)) ->
    refine (Pick (fun prog1 => forall init_state final_state,
                                 precond init_state ->
                                 RunsTo env prog1 init_state final_state ->
                                 MapsTo retvar (SCA av w1) final_state
                                 /\ postcond final_state))
           (ret (Assign retvar (SyntaxExpr.Const w1))).
Proof.
  unfold refine; intros; constructor; intros; inversion_by computes_to_inv; subst.
  inversion_clear H3.
  unfold eval in H1.
  apply Some_inj, SCA_inj in H1; subst.

  unfold cond_respects_MapEq in *.
  rewrite H4; clear H4.

  split.
  apply StringMapFacts.M.add_1; reflexivity.
  intuition.
Qed.

Tactic Notation "cleanup" :=
  first [ simplify with monad laws | spam ].

Import Memory.

Goal forall w1 w2: W, 
     exists x, 
       refine (ret (if Word.weqb w1 w2 then (IL.natToW 3) else (IL.natToW 4))) x.
Proof.
  eexists.

  setoid_rewrite (start_compiling "$ret" (list W)).
  
  setoid_rewrite (compile_if "$cond"); cleanup.
  setoid_rewrite (compile_test IL.Eq "$cond" "$w1" "$w2"); cleanup.
  
  setoid_rewrite (compile_constant "$w1"); cleanup.
  setoid_rewrite (compile_constant "$w2"); cleanup.
  rewrite (compile_constant "$ret"); cleanup.
  rewrite (compile_constant "$ret"); cleanup.
  
  reflexivity.
Qed.

(*
setoid_rewrite (compile_constant "$ret" _ _ _ (fun s => Word.weqb w1 w2 = true /\ True /\ _ s)); cleanup.
setoid_rewrite (compile_constant "$ret" _ _ _ (fun s => Word.weqb w1 w2 = false /\ True /\ _ s)); cleanup.
*)

Goal exists x, 
       refine (ret (Word.wmult 
                      (Word.wplus  (IL.natToW 3) (IL.natToW 4)) 
                      (Word.wminus (IL.natToW 5) (IL.natToW 6)))) x.
Proof.
  eexists.
  
  setoid_rewrite (start_compiling "$ret" (list W)).
  setoid_rewrite (compile_binop IL.Times "$ret" "$t1" "$t2"); cleanup.
  
  setoid_rewrite (compile_binop IL.Plus  "$t1" "$t11" "$t12"); cleanup.
  setoid_rewrite (compile_constant "$t11"); cleanup.
  setoid_rewrite (compile_constant "$t12"); cleanup. 
  
  setoid_rewrite (compile_binop IL.Minus "$t2" "$t21" "$t22"); cleanup.
  setoid_rewrite (compile_constant "$t21"); cleanup.
  setoid_rewrite (compile_constant "$t22"); cleanup.
  
  reflexivity.
Qed.
