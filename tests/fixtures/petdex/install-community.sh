#!/bin/sh
set -e
PETDEX_REFERER="https://petdex.dev/"
DISPLAY_NAME='Cat Sam'
PET_DIR="$HOME/.hermes/pets/cat-sam"
mkdir -p "$PET_DIR"
curl -fsSL -e "$PETDEX_REFERER" -o "$PET_DIR/pet.json" 'https://assets.petdex.dev/pets/cat-sam-9f3a1c/petjson.json'
curl -fsSL -e "$PETDEX_REFERER" -o "$PET_DIR/spritesheet.webp" 'https://assets.petdex.dev/pets/cat-sam-9f3a1c/sprite.webp'
echo "Installed $DISPLAY_NAME"
