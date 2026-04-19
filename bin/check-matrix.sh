#!/bin/sh
# bin/check-matrix.sh

MATRIX_LIST="hello-a hello-b hello-c"
EXCLUDED="lib bin .harness .git docs"
MISSING=""

for dir in */; do
  container=$(basename "$dir")

  # Skip known non-container directories
  case " $EXCLUDED " in
    *" $container "*) continue ;;
  esac

  # Check if it is in the matrix
  case " $MATRIX_LIST " in
    *" $container "*) ;;
    *) MISSING="$MISSING $container" ;;
  esac
done

if [ -n "$MISSING" ]; then
  echo "ERROR: The following container folders are not declared in the pipeline matrix:"
  for m in $MISSING; do
    echo "  - $m"
  done
  echo ""
  echo "Add them to the matrix in pr-pipeline.yaml and main-pipeline.yaml before merging."
  exit 1
fi

echo "Matrix check passed. All container folders are accounted for."
