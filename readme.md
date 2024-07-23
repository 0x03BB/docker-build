# Docker Build

This script reads the ".\images.txt" file to determine which repositories to update and build. The format of the file is one image per line, with each line containing 1) the directory/name of the image, 2) the address of the Git repository of the image, and optionally 3) the Docker registry to use. The information *must* be tab delimited (not space). Example:

my-program	https://github.com/my-git-account/my-program.git	my-registry/

Each repository is cloned or pulled, and must contain the subdirectory "compose-build" with a docker-compose.yml file to build the image. The built image is tagged with the Git tag of the HEAD commit (if present) combined with the current date. The image is also tagged "latest".

Optionally, a single image from ".\images.txt" can be built instead of all images by supplying the -Image parameter.