# Copyright (c) 2025 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

set -e

./create-network.sh
./create-adb.sh
./create-data-lake-storage.sh
./create-compute-vm.sh