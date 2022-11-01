# to create images before test (vicious circle ? :-)
# compile with -d:create

import chroma, pixie, pixie/internal, vmath, xrays
import pixie/imageplanes
import strformat

block:
  const
    fn_base = "tests/images"
    fn_yellow = fmt"{fn_base}/planes_flip_yellow.png"
    fn_yellow_alpha = fmt"{fn_base}/planes_flip_yellow_alpha.png"
    fn_alpha = fmt"{fn_base}/planes_flip_alpha.png"
    fn_RGBA_0 = fmt"{fn_base}/planes_flip_RGBA_0.png"
    fn_RGBA_1 = fmt"{fn_base}/planes_flip_RGBA_1.png"
    fn_RGBA_2 = fmt"{fn_base}/planes_flip_RGBA_2.png"
    fn_RGBA_3 = fmt"{fn_base}/planes_flip_RGBA_3.png"
    fn_gray_0 = fmt"{fn_base}/planes_flip_Gray_0.png"
    fn_gray_1 = fmt"{fn_base}/planes_flip_Gray_1.png"
    fn_gray_2 = fmt"{fn_base}/planes_flip_Gray_2.png"
    fn_gray_3 = fmt"{fn_base}/planes_flip_Gray_3.png"

  let
    a = newImage(80, 80)
    y = newImage(64, 64)
    b = newImage(32, 32)
    g = newImage(32, 32)
    r = newImage(32, 32)
    k = newImage(32, 32)

  a.fill(rgba(96, 192, 192, 255))
  y.fill(rgba(255, 255, 0, 255))
  b.fill(rgba(0, 0, 255, 255))
  g.fill(rgba(0, 255, 0, 255))
  r.fill(rgba(255, 0, 0, 255))
  # k.fill(rgbx(255, 0, 255, 64)) # Premultiplied alpha (not rgba())
  k.fill(rgba(255, 0, 255, 192))
  y.draw(b)
  y.flipVertical()
  y.draw(g)
  y.flipHorizontal()
  y.draw(r)
  y.draw(k, translate(vec2(16, 16)))
  when defined(create): # create before test
    y.writeFile(fn_yellow)
  y.xray(fn_yellow) # -> 0.0
  block: # alpha test
    for j in 24..<40:
      for i in 24..<40:
        y.data[y.dataIndex(i, j)].a = 128
    for j in 28..<36:
      for i in 28..<36:
        y.data[y.dataIndex(i, j)].a = 0
    y.data.toPremultipliedAlpha # must call after change alpha direct
  when defined(create): # create before test
    y.writeFile(fn_yellow_alpha)
  y.xray(fn_yellow_alpha) # -> 0.0
  a.draw(y, translate(vec2(8, 8)))
  block: # alpha test on split merge
    for j in 0..<16:
      for i in 0..<16:
        a.data[a.dataIndex(i, j)].a = 64
    for j in 64..<80:
      for i in 64..<80:
        a.data[a.dataIndex(i, j)].a = 0
    a.data.toPremultipliedAlpha # must call after change alpha direct

  when defined(create): # create before test
    a.toGray.toRGBA.writeFile(fn_gray_0)
    a.writeFile(fn_RGBA_0)
    a.flipVertical()
    a.toGray.toRGBA.writeFile(fn_gray_1)
    a.writeFile(fn_RGBA_1)
    a.flipHorizontal()
    a.toGray.toRGBA.writeFile(fn_gray_2)
    a.writeFile(fn_RGBA_2)
    a.flipVertical()
    # a.toGray(toGrayCustomAW, toStraightAlpha).toRGBA(toRGBAcustomA).writeFile(fn_gray_3)
    a.toGray(toGrayCustomAW).toRGBA(toRGBAcustomA).writeFile(fn_gray_3)
    a.writeFile(fn_RGBA_3)

    a.flipHorizontal() # home position

  # change order gray after RGBA between writing and reading
  a.xray(fn_RGBA_0)
  a.toGray.toRGBA.xray(fn_gray_0)
  a.flipVertical()
  a.xray(fn_RGBA_1)
  a.toGray.toRGBA.xray(fn_gray_1)
  a.flipHorizontal()
  a.xray(fn_RGBA_2)
  a.toGray.toRGBA.xray(fn_gray_2)
  a.flipVertical()
  a.xray(fn_RGBA_3)
  # a.toGray(toGrayCustomAW, toStraightAlpha).toRGBA(toRGBAcustomA).xray(fn_gray_3)
  a.toGray(toGrayCustomAW).toRGBA(toRGBAcustomA).xray(fn_gray_3)

  let fno = fmt"{fn_base}/planes_merge.png"
  when defined(create): # create before test
    a.writeFile(fno)

  var cvt: seq[proc(gr: uint8): ColorRGBA {.inline.}]
  when true:
    when true: # cvt[3] as toRGBAcustomA (xray -> 0.0 looks like gray)
      cvt = @[toRGBAcustomR, toRGBAcustomG, toRGBAcustomB, toRGBAcustomA]
    else: # cvt[3] as toRGBAcustomAW (xray -> 0.0 looks like white)
      cvt = @[toRGBAcustomR, toRGBAcustomG, toRGBAcustomB, toRGBAcustomAW]
  else:
    when false: # cvt[3] as toRGBAcustomAK (rgb xray -> 0.0 alpha xray != 0.0)
      cvt = @[toRGBAcustomR, toRGBAcustomG, toRGBAcustomB, toRGBAcustomAK]
    else: # cvt[3] as toRGBA (always 255 xray -> 0.0 but alpha will be lost)
      cvt = @[toRGBAcustomR, toRGBAcustomG, toRGBAcustomB, toRGBA]
  let p = a.split
  for i in 0..<p.len:
    let fni = fmt"{fn_base}/planes_split_{i}.png"
    when defined(create): # create before test
      p[i].toRGBA(cvt[i]).writeFile(fni)
    p[i].toRGBA(cvt[i]).xray(fni)

  let q = p.merge
  q.xray(fno)

  # test split and merge alpha
  let
    yplanes = fn_yellow.readImage.split
    aplanes = fn_yellow_alpha.readImage.split
    a255 = newImage(64, 64)
    # a192 = newImage(32, 32)
    a128 = newImage(16, 16)
    a0 = newImage(8, 8)
  @[yplanes[0], yplanes[1], yplanes[2]].merge.xray(fn_yellow) # no alpha
  @[yplanes[0], yplanes[1], yplanes[2], aplanes[3]].merge.xray(fn_yellow_alpha)

  # check alpha and toGray
  # to correct accuracy, moved floating point precision (multiply 1000 uint32)
  a255.fill(rgba(255, 255, 255, 255))
  # a192.fill(rgba(192, 192, 192, 255)) # not rgba(255, 255, 255, 192)
  a128.fill(rgba(128, 128, 128, 255)) # not rgba(255, 255, 255, 128)
  a0.fill(rgba(0, 0, 0, 255)) # not rgba(255, 255, 255, 0)
  # a255.draw(a192, translate(vec2(16, 16)))
  a255.draw(a128, translate(vec2(24, 24)))
  a255.draw(a0, translate(vec2(28, 28)))
  let alpha = a255.toGray
  when defined(create): # create before test
    aplanes[3].toRGBA.writeFile(fn_alpha)
    # alpha.toRGBA.writeFile(fn_alpha)
  alpha.toRGBA.xray(fn_alpha)
  @[yplanes[0], yplanes[1], yplanes[2], alpha].merge.xray(fn_yellow_alpha)
