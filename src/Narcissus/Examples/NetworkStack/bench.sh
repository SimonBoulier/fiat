#!/usr/bin/env sh
ocamlopt -config
cp ../../../../Fiat4Mirage.ml ./ || exit 1
rm -f Fiat4Mirage.mli
ocamlfind ocamlopt -g -p -linkpkg -thread -package cstruct -package core -package core_bench \
          -I ../../OCamlExtraction/ \
          ../../OCamlExtraction/Int64Word.ml \
          ../../OCamlExtraction/ArrayVector.ml \
          ../../OCamlExtraction/StackVector.ml \
          ../../OCamlExtraction/CstructBytestring.ml \
          ../../OCamlExtraction/OCamlNativeInt.ml \
          Fiat4Mirage.ml \
          bench.ml \
          -o fiat4mirage-bench || exit 1
time ./fiat4mirage-bench -width 2000 -quota 5 -ci-absolute +time
#short, tall, line, blank or column
