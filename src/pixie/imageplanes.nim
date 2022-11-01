import blends, bumpy, chroma, common, internal, simd, vmath

# export ImagePlane, copy, dataIndex, newImagePlane

type
  ImagePlane* = ref object
    w*, h*: int
    px*: seq[uint8]

  UnsafeImagePlane = distinct ImagePlane

when defined(release):
  {.push checks: off.}

proc newImagePlane*(w, h: int): ImagePlane {.raises: [PixieError].} =
  ## Creates a new image plane with the parameter dimensions.
  if w <= 0 or h <= 0:
    raise newException(PixieError, "ImagePlane width and height must be > 0")

  result = ImagePlane(w: w, h: h, px: newSeq[uint8](w * h))

proc copy*(imageplane: ImagePlane): ImagePlane {.raises: [].} =
  ## Copies the image plane data into a new imagePlane.
  result = ImagePlane(w: imageplane.w, h: imageplane.h, px: imageplane.px)

template dataIndex*(imageplane: ImagePlane, x, y: int): int =
  imageplane.w * y + x

proc toGray*(rgba: ColorRGBA): uint8 {.inline, raises: [].} =
  # to correct accuracy, moved floating point precision (multiply 1000 uint32)
  # 0.2126R + 0.7152G + 0.0722B = Y of CIE XYZ
  # 0.300R + 0.590G + 0.110B NTSC/PAL
  # 0.299R + 0.587G + 0.114B ITU-R Rec BT.601
  const
    fr: uint32 = (299 * 255).uint32
    fg: uint32 = (587 * 255).uint32
    fb: uint32 = (114 * 255).uint32
    # fa: uint32 = (1000 * 255).uint32
    p: uint32 = 1000 * 255
    q: uint32 = 1000 * 127
  let
    r: uint8 = ((rgba.r * fr + q) div p).uint8
    g: uint8 = ((rgba.g * fg + q) div p).uint8
    b: uint8 = ((rgba.b * fb + q) div p).uint8
    # a: uint8 = ((rgba.a * fa + q) div p).uint8
  result = r + g + b

proc toGrayCustomAW*(rgba: ColorRGBA): uint8 {.inline.} =
  result = (if rgba.a == 0: 0xff'u8 else: rgba.toGray)

proc toGray*(im: Image,
  cvt: proc(rgba: ColorRGBA): uint8 {.inline.}=toGray,
  preProcessAlpha: proc(data: var seq[ColorRGBX])=nil): # toStraightAlpha etc
  ImagePlane= # {.hasSimd, raises: [].} =
  # expects im is a 4ch RGBX
  let cp = im.copy
  if preProcessAlpha != nil:
    # cp.data.toStraightAlpha # skip call before get RGBA from RGBX
    cp.data.preProcessAlpha
  result = newImagePlane(cp.width, cp.height)
  for i in 0..<result.px.len:
    result.px[i] = cast[ColorRGBA](cp.data[i]).cvt

proc toRGBAcustomR*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(gr, 0, 0, 255) # always 255

proc toRGBAcustomG*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(0, gr, 0, 255) # always 255

proc toRGBAcustomB*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(0, 0, gr, 255) # always 255

proc toRGBAcustomA*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(0, 0, 0, gr) # rgb always 0 (multiplied later)

proc toRGBAcustomAW*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(255, 255, 255, gr) # rgb always 255 (multiplied later)

proc toRGBAcustomAK*(gr: uint8): ColorRGBA {.inline.} =
  result = rgba(gr, gr, gr, if gr == 255: 0 else: 255) # (multiplied later)

proc toRGBA*(gr: uint8): ColorRGBA {.inline, raises: [].} =
  result = rgba(gr, gr, gr, 255) # toRGBAcustom* when needs other converts

proc toRGBA*(gi: ImagePlane,
  cvt: proc(gr: uint8): ColorRGBA {.inline.}=toRGBA):
  Image= # {.hasSimd, raises: [].} =
  # expects gi is a 1ch grayscale
  result = newImage(gi.w, gi.h)
  for i in 0..<result.data.len:
    result.data[i] = cast[ColorRGBX](gi.px[i].cvt)
  result.data.toPremultipliedAlpha # must call after change alpha direct

proc split*(im: Image): seq[ImagePlane]= # {.hasSimd, raises: [].} =
  # expects im is a 4ch RGBX
  let cp = im.copy
  cp.data.toStraightAlpha # must call before get RGBA from RGBX
  result = newSeq[ImagePlane](4)
  for i in 0..<result.len:
    result[i] = newImagePlane(cp.width, cp.height)
    for j in 0..<result[i].px.len:
      let rgba = cp.data[j]
      result[i].px[j] = cast[array[4, uint8]](rgba)[i]

proc merge*(prgba: seq[ImagePlane]): Image= # {.hasSimd, raises: [].} =
  assert prgba.len == 3 or prgba.len == 4
  let
    w = prgba[0].w
    h = prgba[0].h
  result = newImage(w, h) # expects 4ch RGBX
  for j in 0..<result.data.len:
    let a: uint8 = if prgba.len == 4: prgba[3].px[j] else: 255
    result.data[j] = rgbx(prgba[0].px[j], prgba[1].px[j], prgba[2].px[j], a)
  result.data.toPremultipliedAlpha # must call after change alpha direct

when defined(release):
  {.pop.}
