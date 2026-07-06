## x11_icons.nim — optional Imlib2 icon rendering for X11.
## MIT; see LICENSE for details.
##
## Imported only with -d:icons. Default builds do not link against Imlib2.

{.passL: "-lImlib2".}

import x11/[xlib, x]
import ./state

type ImlibImage = pointer

proc imlib_context_set_display(d: pointer) {.importc, header: "<Imlib2.h>".}
proc imlib_context_set_visual(v: pointer) {.importc, header: "<Imlib2.h>".}
proc imlib_context_set_colormap(c: Colormap) {.importc, header: "<Imlib2.h>".}
proc imlib_context_set_drawable(d: Drawable) {.importc, header: "<Imlib2.h>".}
proc imlib_context_set_image(image: ImlibImage) {.importc, header: "<Imlib2.h>".}
proc imlib_load_image(file: cstring): ImlibImage {.importc, header: "<Imlib2.h>".}
proc imlib_image_get_width(): cint {.importc, header: "<Imlib2.h>".}
proc imlib_image_get_height(): cint {.importc, header: "<Imlib2.h>".}
proc imlib_render_image_on_drawable_at_size(x, y, w, h: cint) {.importc,
    header: "<Imlib2.h>".}
proc imlib_free_image() {.importc, header: "<Imlib2.h>".}

proc initIconRenderer*() =
  ## Bind Imlib2 to the current X11 window.
  imlib_context_set_display(cast[pointer](display))
  imlib_context_set_visual(cast[pointer](DefaultVisual(display, screen)))
  imlib_context_set_colormap(DefaultColormap(display, screen))
  imlib_context_set_drawable(window.Drawable)

proc drawIcon*(path: string; x, y, size: cint): bool =
  ## Draw icon top-left at x/y scaled to size. Returns false on load failure.
  if path.len == 0 or size <= 0:
    return false
  let image = imlib_load_image(path.cstring)
  if image.isNil:
    return false
  imlib_context_set_image(image)
  let w = imlib_image_get_width()
  let h = imlib_image_get_height()
  if w > 0 and h > 0:
    imlib_render_image_on_drawable_at_size(x, y, size, size)
    result = true
  imlib_free_image()
