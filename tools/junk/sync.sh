#!/bin/sh
# Copies the shared junk rules from Gulli-Merchant (the original) into Gulli-BagSpace.
# Run from the repository root after changing Gulli-Merchant/Junk.lua.
set -e
cp Gulli-Merchant/Junk.lua Gulli-BagSpace/Junk.lua
echo "Gulli-BagSpace/Junk.lua updated"
