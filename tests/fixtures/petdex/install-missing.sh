#!/bin/sh
set -e
PETDEX_REFERER="https://petdex.dev/"
DISPLAY_NAME='Boba'
PET_DIR="$HOME/.hermes/pets/boba"
mkdir -p "$PET_DIR"
curl -fsSL -e "$PETDEX_REFERER" -o "$PET_DIR/pet.json" 'https://assets.petdex.dev/curated/boba/petjson-v2.json'
echo "Installed $DISPLAY_NAME"
