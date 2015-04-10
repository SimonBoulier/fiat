(** * Definition of ε, the CFG accepting only "" *)
Require Import Coq.Strings.String Coq.Lists.List.
Require Import ADTSynthesis.Parsers.ContextFreeGrammar.

Set Implicit Arguments.

Section generic.
  Context {Char} {HSL : StringLike Char}.

  Definition trivial_grammar : grammar Char :=
    {| Start_symbol := "";
       Lookup := fun _ => nil::nil;
       Valid_nonterminals := ""%string::nil |}.

  Definition trivial_grammar_parses_empty_string {s} (H : length s = 0)
  : parse_of_grammar s trivial_grammar.
  Proof.
    hnf; simpl.
    apply ParseHead.
    constructor; assumption.
  Defined.

  Lemma trivial_grammar_parses_only_empty_string s : parse_of_grammar s trivial_grammar -> length s = 0.
  Proof.
    intro H; hnf in H; simpl in H.
    repeat match goal with
             | _ => reflexivity
             | _ => assumption
             | [ H : parse_of _ _ _ |- _ ] => inversion_clear H
             | [ H : parse_of_production _ _ _ |- _ ] => inversion_clear H
           end.
  Qed.
End generic.