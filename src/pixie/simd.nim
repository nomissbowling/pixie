import chroma

when defined(release):
  {.push checks: off.}

when defined(amd64):
  import nimsimd/runtimecheck, nimsimd/sse2, runtimechecked/avx,
      runtimechecked/avx2

  let
    cpuHasAvx* = checkInstructionSets({AVX})
    cpuHasAvx2* = checkInstructionSets({AVX, AVX2})

  proc packAlphaValues(v: M128i): M128i {.inline.} =
    ## Shuffle the alpha values for these 4 colors to the first 4 bytes.
    result = mm_srli_epi32(v, 24)
    result = mm_packus_epi16(result, mm_setzero_si128())
    result = mm_packus_epi16(result, mm_setzero_si128())

  proc pack4xAlphaValues*(i, j, k, l: M128i): M128i {.inline.} =
    let
      i = packAlphaValues(i)
      j = mm_slli_si128(packAlphaValues(j), 4)
      k = mm_slli_si128(packAlphaValues(k), 8)
      l = mm_slli_si128(packAlphaValues(l), 12)
    mm_or_si128(mm_or_si128(i, j), mm_or_si128(k, l))

  proc unpackAlphaValues*(v: M128i): M128i {.inline, raises: [].} =
    ## Unpack the first 32 bits into 4 rgba(0, 0, 0, value).
    result = mm_unpacklo_epi8(mm_setzero_si128(), v)
    result = mm_unpacklo_epi8(mm_setzero_si128(), result)

  proc fillUnsafeSimd*(
    data: var seq[ColorRGBX],
    start, len: int,
    color: SomeColor
  ) =
    if cpuHasAvx:
      fillUnsafeAvx(data, start, len, color)
      return

    let rgbx = color.asRgbx()

    var
      i = start
      p = cast[uint](data[i].addr)
    # Align to 16 bytes
    while i < (start + len) and (p and 15) != 0:
      data[i] = rgbx
      inc i
      p += 4

    let
      colorVec = mm_set1_epi32(cast[int32](rgbx))
      iterations = (start + len - i) div 8
    for _ in 0 ..< iterations:
      mm_store_si128(cast[pointer](p), colorVec)
      mm_store_si128(cast[pointer](p + 16), colorVec)
      p += 32
    i += iterations * 8

    for i in i ..< start + len:
      data[i] = rgbx

  proc isOneColorSimd*(data: var seq[ColorRGBX]): bool =
    if cpuHasAvx2:
      return isOneColorAvx2(data)

    result = true

    let color = data[0]

    var
      i: int
      p = cast[uint](data[0].addr)
    # Align to 16 bytes
    while i < data.len and (p and 15) != 0:
      if data[i] != color:
        return false
      inc i
      p += 4

    let
      colorVec = mm_set1_epi32(cast[int32](color))
      iterations = (data.len - i) div 16
    for _ in 0 ..< iterations:
      let
        values0 = mm_load_si128(cast[pointer](p))
        values1 = mm_load_si128(cast[pointer](p + 16))
        values2 = mm_load_si128(cast[pointer](p + 32))
        values3 = mm_load_si128(cast[pointer](p + 48))
        eq0 = mm_cmpeq_epi8(values0, colorVec)
        eq1 = mm_cmpeq_epi8(values1, colorVec)
        eq2 = mm_cmpeq_epi8(values2, colorVec)
        eq3 = mm_cmpeq_epi8(values3, colorVec)
        eq0123 = mm_and_si128(mm_and_si128(eq0, eq1), mm_and_si128(eq2, eq3))
      if mm_movemask_epi8(eq0123) != 0xffff:
        return false
      p += 64
    i += 16 * iterations

    for i in i ..< data.len:
      if data[i] != color:
        return false

  proc isTransparentSimd*(data: var seq[ColorRGBX]): bool =
    if cpuHasAvx2:
      return isTransparentAvx2(data)

    var
      i: int
      p = cast[uint](data[0].addr)
    # Align to 16 bytes
    while i < data.len and (p and 15) != 0:
      if data[i].a != 0:
        return false
      inc i
      p += 4

    result = true

    let
      vecZero = mm_setzero_si128()
      iterations = (data.len - i) div 16
    for _ in 0 ..< iterations:
      let
        values0 = mm_load_si128(cast[pointer](p))
        values1 = mm_load_si128(cast[pointer](p + 16))
        values2 = mm_load_si128(cast[pointer](p + 32))
        values3 = mm_load_si128(cast[pointer](p + 48))
        values01 = mm_or_si128(values0, values1)
        values23 = mm_or_si128(values2, values3)
        values0123 = mm_or_si128(values01, values23)
      if mm_movemask_epi8(mm_cmpeq_epi8(values0123, vecZero)) != 0xffff:
        return false
      p += 64
    i += 16 * iterations

    for i in i ..< data.len:
      if data[i].a != 0:
        return false

  proc isOpaqueSimd*(data: var seq[ColorRGBX], start, len: int): bool =
    if cpuHasAvx2:
      return isOpaqueAvx2(data, start, len)

    result = true

    var
      i = start
      p = cast[uint](data[0].addr)
    # Align to 16 bytes
    while i < (start + len) and (p and 15) != 0:
      if data[i].a != 255:
        return false
      inc i
      p += 4

    let
      vec255 = mm_set1_epi8(255)
      iterations = (start + len - i) div 16
    for _ in 0 ..< iterations:
      let
        values0 = mm_load_si128(cast[pointer](p))
        values1 = mm_load_si128(cast[pointer](p + 16))
        values2 = mm_load_si128(cast[pointer](p + 32))
        values3 = mm_load_si128(cast[pointer](p + 48))
        values01 = mm_and_si128(values0, values1)
        values23 = mm_and_si128(values2, values3)
        values0123 = mm_and_si128(values01, values23)
        eq = mm_cmpeq_epi8(values0123, vec255)
      if (mm_movemask_epi8(eq) and 0x00008888) != 0x00008888:
        return false
      p += 64
    i += 16 * iterations

    for i in i ..< start + len:
      if data[i].a != 255:
        return false

  proc toPremultipliedAlphaSimd*(data: var seq[ColorRGBA | ColorRGBX]) =
    if cpuHasAvx2:
      toPremultipliedAlphaAvx2(data)
      return

    var i: int

    let
      alphaMask = mm_set1_epi32(cast[int32](0xff000000))
      oddMask = mm_set1_epi16(0xff00)
      div255 = mm_set1_epi16(0x8081)
      iterations = data.len div 4
    for _ in 0 ..< iterations:
      let
        values = mm_loadu_si128(data[i].addr)
        alpha = mm_and_si128(values, alphaMask)
        eq = mm_cmpeq_epi8(values, alphaMask)
      if (mm_movemask_epi8(eq) and 0x00008888) != 0x00008888:
        let
          evenMultiplier = mm_or_si128(alpha, mm_srli_epi32(alpha, 16))
          oddMultiplier = mm_or_si128(evenMultiplier, alphaMask)
        var
          colorsEven = mm_slli_epi16(values, 8)
          colorsOdd = mm_and_si128(values, oddMask)
        colorsEven = mm_mulhi_epu16(colorsEven, evenMultiplier)
        colorsOdd = mm_mulhi_epu16(colorsOdd, oddMultiplier)
        colorsEven = mm_srli_epi16(mm_mulhi_epu16(colorsEven, div255), 7)
        colorsOdd = mm_srli_epi16(mm_mulhi_epu16(colorsOdd, div255), 7)
        mm_storeu_si128(
          data[i].addr,
          mm_or_si128(colorsEven, mm_slli_epi16(colorsOdd, 8))
        )
      i += 4

    for i in i ..< data.len:
      var c = data[i]
      if c.a != 255:
        c.r = ((c.r.uint32 * c.a) div 255).uint8
        c.g = ((c.g.uint32 * c.a) div 255).uint8
        c.b = ((c.b.uint32 * c.a) div 255).uint8
        data[i] = c

  proc newImageFromMaskSimd*(dst: var seq[ColorRGBX], src: var seq[uint8]) =
    var i: int
    for _ in 0 ..< src.len div 16:
      var alphas = mm_loadu_si128(src[i].addr)
      for j in 0 ..< 4:
        var unpacked = unpackAlphaValues(alphas)
        unpacked = mm_or_si128(unpacked, mm_srli_epi32(unpacked, 8))
        unpacked = mm_or_si128(unpacked, mm_srli_epi32(unpacked, 16))
        mm_storeu_si128(dst[i + j * 4].addr, unpacked)
        alphas = mm_srli_si128(alphas, 4)
      i += 16

    for i in i ..< src.len:
      let v = src[i]
      dst[i] = rgbx(v, v, v, v)

  proc newMaskFromImageSimd*(dst: var seq[uint8], src: var seq[ColorRGBX]) =
    var i: int
    for _ in 0 ..< src.len div 16:
      let
        a = mm_loadu_si128(src[i + 0].addr)
        b = mm_loadu_si128(src[i + 4].addr)
        c = mm_loadu_si128(src[i + 8].addr)
        d = mm_loadu_si128(src[i + 12].addr)
      mm_storeu_si128(
        dst[i].addr,
        pack4xAlphaValues(a, b, c, d)
      )
      i += 16

    for i in i ..< src.len:
      dst[i] = src[i].a

  proc invertImageSimd*(data: var seq[ColorRGBX]) =
    var
      i: int
      p = cast[uint](data[0].addr)
    # Align to 16 bytes
    while i < data.len and (p and 15) != 0:
      var rgbx = data[i]
      rgbx.r = 255 - rgbx.r
      rgbx.g = 255 - rgbx.g
      rgbx.b = 255 - rgbx.b
      rgbx.a = 255 - rgbx.a
      data[i] = rgbx
      inc i
      p += 4

    let
      vec255 = mm_set1_epi8(255)
      iterations = data.len div 16
    for _ in 0 ..< iterations:
      let
        a = mm_load_si128(cast[pointer](p))
        b = mm_load_si128(cast[pointer](p + 16))
        c = mm_load_si128(cast[pointer](p + 32))
        d = mm_load_si128(cast[pointer](p + 48))
      mm_store_si128(cast[pointer](p), mm_sub_epi8(vec255, a))
      mm_store_si128(cast[pointer](p + 16), mm_sub_epi8(vec255, b))
      mm_store_si128(cast[pointer](p + 32), mm_sub_epi8(vec255, c))
      mm_store_si128(cast[pointer](p + 48), mm_sub_epi8(vec255, d))
      p += 64
    i += 16 * iterations

    for i in i ..< data.len:
      var rgbx = data[i]
      rgbx.r = 255 - rgbx.r
      rgbx.g = 255 - rgbx.g
      rgbx.b = 255 - rgbx.b
      rgbx.a = 255 - rgbx.a
      data[i] = rgbx

    toPremultipliedAlphaSimd(data)

  proc invertMaskSimd*(data: var seq[uint8]) =
    var
      i: int
      p = cast[uint](data[0].addr)
    # Align to 16 bytes
    while i < data.len and (p and 15) != 0:
      data[i] = 255 - data[i]
      inc i
      inc p

    let
      vec255 = mm_set1_epi8(255)
      iterations = data.len div 64
    for _ in 0 ..< iterations:
      let
        a = mm_load_si128(cast[pointer](p))
        b = mm_load_si128(cast[pointer](p + 16))
        c = mm_load_si128(cast[pointer](p + 32))
        d = mm_load_si128(cast[pointer](p + 48))
      mm_store_si128(cast[pointer](p), mm_sub_epi8(vec255, a))
      mm_store_si128(cast[pointer](p + 16), mm_sub_epi8(vec255, b))
      mm_store_si128(cast[pointer](p + 32), mm_sub_epi8(vec255, c))
      mm_store_si128(cast[pointer](p + 48), mm_sub_epi8(vec255, d))
      p += 64
    i += 64 * iterations

    for i in i ..< data.len:
      data[i] = 255 - data[i]

  proc ceilMaskSimd*(data: var seq[uint8]) =
    var
      i: int
      p = cast[uint](data[0].addr)

    let
      zeroVec = mm_setzero_si128()
      vec255 = mm_set1_epi8(255)
      iterations = data.len div 16
    for _ in 0 ..< iterations:
      var values = mm_loadu_si128(cast[pointer](p))
      values = mm_cmpeq_epi8(values, zeroVec)
      values = mm_andnot_si128(values, vec255)
      mm_storeu_si128(cast[pointer](p), values)
      p += 16
    i += 16 * iterations

    for i in i ..< data.len:
      if data[i] != 0:
        data[i] = 255

  proc applyOpacitySimd*(data: var seq[uint8 | ColorRGBX], opacity: uint16) =
    var
      i: int
      p = cast[uint](data[0].addr)
      len =
        when data is seq[ColorRGBX]:
          data.len * 4
        else:
          data.len

    let
      oddMask = mm_set1_epi16(0xff00)
      div255 = mm_set1_epi16(0x8081)
      zeroVec = mm_setzero_si128()
      opacityVec = mm_slli_epi16(mm_set1_epi16(opacity), 8)
      iterations = len div 16
    for _ in 0 ..< len div 16:
      let values = mm_loadu_si128(cast[pointer](p))
      if mm_movemask_epi8(mm_cmpeq_epi16(values, zeroVec)) != 0xffff:
        var
          valuesEven = mm_slli_epi16(values, 8)
          valuesOdd = mm_and_si128(values, oddMask)
        valuesEven = mm_mulhi_epu16(valuesEven, opacityVec)
        valuesOdd = mm_mulhi_epu16(valuesOdd, opacityVec)
        valuesEven = mm_srli_epi16(mm_mulhi_epu16(valuesEven, div255), 7)
        valuesOdd = mm_srli_epi16(mm_mulhi_epu16(valuesOdd, div255), 7)
        mm_storeu_si128(
          cast[pointer](p),
          mm_or_si128(valuesEven, mm_slli_epi16(valuesOdd, 8))
        )
      p += 16
    i += 16 * iterations

    when data is seq[ColorRGBX]:
      for i in i div 4 ..< data.len:
        var rgbx = data[i]
        rgbx.r = ((rgbx.r * opacity) div 255).uint8
        rgbx.g = ((rgbx.g * opacity) div 255).uint8
        rgbx.b = ((rgbx.b * opacity) div 255).uint8
        rgbx.a = ((rgbx.a * opacity) div 255).uint8
        data[i] = rgbx
    else:
      for i in i ..< data.len:
        data[i] = ((data[i] * opacity) div 255).uint8

when defined(release):
  {.pop.}