extends RefCounted
## One small, static panorama. Stars stay at infinity as the camera travels;
## no particles, per-frame noise, light nodes or shared gameplay RNG.
const SIZE := Vector2i(2048,1024)
const STAR_COUNT := 1100
const VOID := Color(0.001,0.003,0.008)

static func create() -> Sky:
	var image := Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGB8)
	image.fill(VOID)
	var random := RandomNumberGenerator.new()
	random.seed = 70419
	for i in range(STAR_COUNT):
		# Uniform directions avoid a dense band of stars around the zenith.
		var height := random.randf_range(0.025,0.999)
		var x := random.randi_range(1,SIZE.x-2)
		var y := clampi(roundi(acos(height)/PI*SIZE.y),1,SIZE.y-2)
		var brightness := random.randf_range(0.34,0.80)
		var color := Color(0.82,0.92,1.0)*brightness
		image.set_pixel(x,y,color)
		for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			image.set_pixel(x+offset.x,y+offset.y,color*(0.20 if i%11==0 else 0.055))
	image.generate_mipmaps()
	var material := PanoramaSkyMaterial.new()
	material.panorama = ImageTexture.create_from_image(image)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.sky_material = material
	return sky
