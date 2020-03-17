# Change Dir Here
cd `dirname $0`
# Compile icons_pack.c
gcc -o icons_pack icons_pack.c -I/usr/include/glib-2.0 \
  -I/usr/include/cairo -I/usr/lib/glib-2.0/include \
  -I/usr/include/librsvg-2.0 -I/usr/include/gdk-pixbuf-2.0 \
  -lcairo -lrsvg-2 -lglib-2.0 -lgobject-2.0 -O2
# Use icons_pack for generate dat file
cd icons && ../icons_pack "../../$1" ${@:2}
# Get finish code
finish_code=$?
# Remove icons_pack
cd .. && rm icons_pack
# Return exit code
exit $finish_code
