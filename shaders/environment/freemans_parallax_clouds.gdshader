// Hoarbound production atmosphere + parallax-cloud sky.
// Upstream: NiwlGames/GodotStarterAssets shaders/sky_full.gdshader (CC0-1.0).
// Freeman uses a dedicated solar direction; HFN clouds keep LIGHT0 for sun/moon lighting.

shader_type sky;
render_mode use_half_res_pass;
group_uniforms Sun;

/**
The intensity of the sun.
Simple Lambertian light contains 1/PI in its formulation. For that reason, PI usually represents a full low dynamic range.
We recommend keeping contrast between the sky and the directional light. The default value assumes a directional light of 10PI and a sky of 20PI.
*/
uniform float sun_intensity : hint_range(0.0, 314.159, 0.1) = 48.0;
uniform vec3 sun_wavelengths = vec3(0.680, 0.550, 0.480);

/*
Rayleigh scattering is the reason why sunsets are red and noons are blue.
Rayleigh happens when the particles are small enough to affect the individual wavelengths of light.
At sunrise/sunset, light coming from the sun has to traverse a much bigger distance towards the eye resulting in most of the surviving light being red because of its larger wavelength.
*/
group_uniforms Atmosphere.Rayleigh;

/**
Defines the thickness of the layer in which Rayleigh scattering happens.
A thicker layer can provide more vibrant reds at sunrise/sunset, but may stain the blue of the sky when the sun is at its zenith.
*/
uniform float rayleigh_scale_height : hint_range(0.0, 100000.0, 1.0) = 9000.0;

/**
Defines the intensity of the Rayleigh multi-bounce approximation.
After many bounces, Rayleigh becomes isotropic. We take advantage of that to "inject" some light in order to avoid pitch black planet shadows.
The injection is done naively, so it is recommended to keep this value as low as possible to prevent contrast loss.
*/
uniform float rayleigh_multi_scattering : hint_range(0.0, 1.0, 0.001 ) = 0.018;

/*
Mie scattering is responsible for the glow around the sun and phenomena such as fog and clouds.
Mie scattering happens when particles are big enough to substantially block light, therefore, the color of the remaining light is mostly unaffected.
Because Mie tends to scatter lots of light, very cloudy scenes may need more samples in order to prevent parts of the sky from becoming black.
*/
group_uniforms Atmosphere.Mie;

/**
Defines the thickness of the layer in which Mie scattering happens.
A thicker layer can create some interesting effects, but for realistic setups it is recommended to increase mie_scattering instead.
*/
uniform float mie_scale_height : hint_range(0.0, 1e5, 1.00) = 1600.0;

/**
The strength of the scattering effect. Lower values result in a clearer day. */
uniform float mie_scattering : hint_range(0.0, 1.0, 1e-7) = 8e-6;
uniform float mie_albedo : hint_range(0.0, 1.0, 0.01) = 0.88;

/**
We use a Double-Lobe Henyey-Greenstein phase function for Mie.
While Mie scatters light predominantly forward, the double lobe allows for a more natural behaviour by scattering some of the light backwards.
The value of the forward lobe.
*/
uniform float mie_g_forward : hint_range(0.0, 1.0,  0.01) = 0.80;

/** The value of the backward lobe. */
uniform float mie_g_backward : hint_range(-1.0, 0.0,  0.01) = -0.15;

/**
The weight used to interpolate between the forward and backward lobes.
This value should usually remain close to one, but lowering it can help convey denser/foggier/humid atmospheres.
*/
uniform float mie_weight : hint_range(0.0, 1.0, 0.01) = 0.78;

/**
Defines the intensity of the Mie multi-bounce approximation.
Unlike Rayleigh, Mie remains anisotropic after many bounces. In order to simulate multiple bounces, we use a secondary softer, less directional lobe.
*/
uniform float mie_multi_scattering : hint_range(0.0, 1.0, 0.01) = 0.24;

/** The multiscattering value of the forward lobe. */
uniform float multiscattering_mie_g_forward : hint_range(0.0, 1.0, 0.01) = 0.5;

/** The multiscattering value of the backward lobe. */
uniform float multiscattering_mie_g_backward : hint_range(-1.0, 0.0, 0.01) = -0.05;

/** The weight used to interpolate between the forward and backward multiscattering lobes. */
uniform float multiscattering_mie_weight : hint_range(0.0, 1.0, 0.01) = 0.75;

/*
The Ozone layer behaves as a purely absorbent medium, subtracting mostly reds and oranges. It is responsible for the electric blues of the "blue hour."
Unlike Rayleigh or Mie, we don't have a specific equation to define its behavior, so we mostly configure the center and width of the layer.
*/
group_uniforms Atmosphere.Ozone;

/* Ozone extinction coefficient */
const vec3 ozone_extinction = vec3(0.650, 1.881, 0.085) * 1e-6;

/** The center of the ozone layer */
uniform float ozone_center : hint_range(0.0, 1e5, 1.00) = 25000.0;

/** The width of the ozone layer */
uniform float ozone_width : hint_range(0.0, 1e5, 1.00) = 30000.0;

/** Planet geometry. */
group_uniforms Planet;

/** The radius of the planet in meters. */
uniform float planet_radius = 6360000.0;

/** The height of the atmosphere from the ground in meters. */
uniform float atmosphere_height = 100000.0;

/**
Base altitude.
The ground will be this many meters below the camera when the camera is at Y = 0.
*/
uniform float base_altitude = 0.0;

/** Ground color. */
uniform vec3 ground_color = vec3(0.12, 0.11, 0.08);

/* HFN parallax cloud layer.
Derived from the project's CC0 Simple Overcast integration. Freeman remains the
physical atmosphere; these uniforms only composite the authored cloud body. */
group_uniforms Clouds;
uniform sampler2D cloud_noise_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 cloud_color : source_color = vec4(0.30, 0.39, 0.48, 1.0);
uniform float cloud_density : hint_range(0.1, 12.0, 0.1) = 4.8;
uniform float cloud_depth : hint_range(0.0, 6.0, 0.1) = 2.35;
uniform float cloud_sag : hint_range(0.25, 6.0, 0.05) = 2.0;
uniform vec2 cloud_noise_tiling = vec2(1.0);
uniform vec2 cloud_wind_speed = vec2(0.24, 0.08);
uniform float cloud_time = 0.0;
uniform float cloud_parallax_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float cloud_parallax_layer_separation : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float cloud_parallax_detail_weight : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float cloud_parallax_mid_scale : hint_range(1.0, 4.0, 0.05) = 1.65;
uniform float cloud_parallax_high_scale : hint_range(1.0, 6.0, 0.05) = 2.55;
uniform float cloud_shape_contrast : hint_range(0.0, 1.0, 0.01) = 0.52;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.34;
/* Sun- or moon-lit cloud tops: thin edges and tops go brighter than the sky, dense bellies stay dark,
which is what makes a cloud read as a volume. 0 keeps the historical dark-slate cloud. */
uniform float cloud_top_light : hint_range(0.0, 1.0, 0.01) = 0.0;
// Legacy name: this value is the cloud-mask threshold. Lower = more visible cloud.
uniform float cloud_coverage : hint_range(0.0, 0.95, 0.01) = 0.34;
// Upper edge of the cloud-mask smoothstep. Lower values make surviving noise
// become a readable cloud body sooner without changing the noise itself.
uniform float cloud_mask_top : hint_range(0.4, 0.95, 0.01) = 0.92;
uniform float cloud_opacity : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform vec4 cloud_sun_color : source_color = vec4(1.0);
uniform float cloud_sun_energy : hint_range(0.0, 32.0, 0.1) = 1.0;
uniform float cloud_light_energy_scale : hint_range(0.1, 20.0, 0.1) = 5.0;
group_uniforms;

uniform float exposure : hint_range(0.0, 4.0, 0.01) = 1.0;

/* Quality and performance settings */
group_uniforms Quality;

/**
The amount of samples along the view path (out-scattering).
Defines the volumetric resolution of the volume.
*/
uniform int view_samples : hint_range(0, 256) = 12;

/**
The amount of samples along the sun path (in-scattering).
Defines how accurately the light traverses the medium.
*/
uniform int sun_samples : hint_range(0, 256) = 4;


/* Returns the full diameter of the atmospheric sphere */
float get_atmosphere_radius(){
	return planet_radius + atmosphere_height;
}


/* Ray-Sphere intersection from Inigo Quilez (https://iquilezles.org/articles/intersectors) */
vec2 ray_sphere_intersection(vec3 ray_origin, vec3 ray_direction, float sphere_radius) {
	float b = dot(ray_origin, ray_direction);
	float c = dot(ray_origin, ray_origin) - sphere_radius * sphere_radius;
	float discriminant = b * b - c;
	
	if (discriminant < 0.0){
		return vec2(-1.0);
	}

	float root = sqrt(discriminant);
	return vec2(-b - root, -b + root);
}


/*
Returns the Rayleigh scattering coefficient based on sun wavelengths.
Rayleigh doesn't absorb light, so we use the coefficient directly.
*/
vec3 get_rayleigh_scattering(){
	return (1.0 / (sun_wavelengths * sun_wavelengths * sun_wavelengths * sun_wavelengths)) * 1e-6;
}


/*
Returns the Mie extinction coefficient.
Unlike Rayleigh, Mie does absorb light. The albedo value represents how much light is preserved (0 - Full absorption, 1 - Full scattering).
*/
float get_mie_extinction(){
	return mie_scattering / mie_albedo;
}


/*
Returns the Rayleigh phase function. This phase has a specific equation, so there is not much to configure.
*/
float get_rayleigh_phase(float cos_theta) {
	// Precomputed 3/16 PI.
	return 0.05968310365 * (1.0 + cos_theta * cos_theta);
}


/*
Simple Henyey-Greenstein. Two of these ellipsoidal functions are used for the final Mie phase calculation.
*/
float henyey_greenstein_phase(float cos_theta, float g) {
	float g2 = g * g;
	// Correct version. Precomputed 1/4 PI.
	return 0.07957747154 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5);
}

/*
Double-lobe Henyey-Greenstein used for Mie. It's just a mix of forward and backward lobes.
*/
float get_mie_phase(float cos_theta, float g_backward, float g_forward, float weight) {
	float backward_phase = henyey_greenstein_phase(cos_theta, g_backward);
	float forward_phase = henyey_greenstein_phase(cos_theta, g_forward);
	return mix(backward_phase, forward_phase, weight);
}


/*
Returns the local density based on the provided scale heights.
Rayleigh on X, Mie on Y, Ozone on Z.
*/
vec3 get_optical_depth_at_point(vec3 position) {
	float altitude = length(position) - planet_radius;
	
	return vec3(
		exp(-altitude / rayleigh_scale_height),
		exp(-altitude / mie_scale_height),
		max(0.0, 1.0 - abs(altitude - ozone_center) / (ozone_width / 2.0))
	);
}


/*
Returns the transmittance along the given atmospheric path.
We use simple Lambert's law to calculate transmittance. To compensate for the exponential
nature of the atmosphere, we use the average of the start and end step densities to get a better
representation of the segment.
Rayleigh on X, Mie on Y, Ozone on Z.
*/
vec3 get_transmittance(vec3 origin, vec3 direction, float dist, int samples) {
	float step_length              = dist / float(samples);
	vec3 accumulated_optical_depth = vec3(0.0);
	vec3 optical_depth_start       = get_optical_depth_at_point(origin);
	
	for (int i = 0; i < samples; i++) {
		vec3 optical_depth_end  = get_optical_depth_at_point(origin + direction * (float(i + 1)) * step_length);
		vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
		
		accumulated_optical_depth += step_optical_depth;
		optical_depth_start        = optical_depth_end;
	}
	
	return exp(-(
		get_rayleigh_scattering() * accumulated_optical_depth.x +
		get_mie_extinction()      * accumulated_optical_depth.y +
		ozone_extinction          * accumulated_optical_depth.z
		));
}

/*
Returns the final atmospheric radiance along a given path.
*/
vec3 integrate_radiance(vec3 ray_origin, vec3 ray_direction, float target_distance, int samples, int sun_sample_count, vec3 sun_direction) {
	float atmosphere_radius = get_atmosphere_radius();
	
	// how similar are the ray and sun directions.
	float cos_theta = dot(ray_direction, sun_direction);
	
	// Distance to cover by each step.
	float step_length = target_distance / float(samples);
	
	// Phases.
	float rayleigh_phase             = get_rayleigh_phase(cos_theta);
	float mie_phase                  = get_mie_phase(cos_theta, mie_g_backward, mie_g_forward, mie_weight);
	float multi_scattering_mie_phase = get_mie_phase(cos_theta, multiscattering_mie_g_backward, multiscattering_mie_g_forward, multiscattering_mie_weight);
	
	// Accumulators
	vec3 accumulated_optical_depth = vec3(0.0);
	vec3 accumulated_radiance      = vec3(0.0);
	vec3 view_transmittance        = vec3(0.0);
	
	// Optical depth at the beginning of the first sample.
	vec3 optical_depth_start = get_optical_depth_at_point(ray_origin);
	bool hits_ground = false;
	
	for (int i = 0; i < samples; i++) {
		
		// Optical deph at the end of the sample.
		vec3 optical_depth_end = get_optical_depth_at_point(ray_origin + ray_direction * float(i + 1) * step_length);
		
		// Average them. Jitter changes the weight of the average.
		vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
		
		// Accumulate the optical depth for this step
		accumulated_optical_depth += step_optical_depth;
		
		vec3 sample_point = ray_origin + ray_direction * (float(i) + 0.5) * step_length;
		
		// Calculate transmittance.
		view_transmittance = exp(-(
			get_rayleigh_scattering() * accumulated_optical_depth.x +
			get_mie_extinction()       * accumulated_optical_depth.y +
			ozone_extinction           * accumulated_optical_depth.z
			));
		
		vec3 sun_radiance = vec3(0.0);
		
		// Planet intersection.
		vec2 planet_hit = ray_sphere_intersection(sample_point, sun_direction, planet_radius);
		
		hits_ground = planet_hit.y > 0.0;
		
		// If the sun is NOT occluded by the planet, calculate sun radiance.
		if (!hits_ground) {
			
			// Atmosphere intersection.
			vec2 atmosphere_hit = ray_sphere_intersection(sample_point, sun_direction, atmosphere_radius);
			vec3 sun_transmittance = get_transmittance(sample_point, sun_direction, atmosphere_hit.y, sun_sample_count);
			vec3 scattering_coeff = (
				step_optical_depth.x * get_rayleigh_scattering() * rayleigh_phase +
				step_optical_depth.y * mie_scattering            * mie_phase
				);
			
			sun_radiance = sun_transmittance * sun_intensity * scattering_coeff;
		}
		
		// Accumulate sun radiance.
		accumulated_radiance += sun_radiance * view_transmittance;
		
		// Multi scattering approximations.
		vec3 rayleigh_ambient = step_optical_depth.x * get_rayleigh_scattering() * rayleigh_multi_scattering;
		vec3 mie_ambient = vec3(step_optical_depth.y * mie_scattering * multi_scattering_mie_phase * mie_multi_scattering);
		
		// Accumulate ambient light.
		accumulated_radiance += (rayleigh_ambient + mie_ambient) * view_transmittance;
		
		// Recycle this end point as the next iteration start point.
		optical_depth_start = optical_depth_end;
	}
	
	vec3 sun_disk = vec3(0.0);
	float planet_hit = ray_sphere_intersection(ray_origin, ray_direction, planet_radius).y;
	
	if (planet_hit < 0.0){
		sun_disk = smoothstep(0.9998, 1.0, cos_theta) * sun_intensity * view_transmittance;
	}
	return accumulated_radiance + sun_disk;
}


/* HFN cloud helpers use a prefix so the upstream Freeman functions remain intact. */
float hfn_cloud_plane_intersection(vec3 ray_direction) {
	float denominator = dot(ray_direction, vec3(0.0, -1.0, 0.0));
	if (abs(denominator) < 0.0001) {
		return -1.0;
	}
	return -1.0 / denominator;
}


float hfn_cloud_height(vec2 uv) {
	float value = texture(cloud_noise_texture, uv).r;
	return pow(clamp(value, 0.0, 1.0), max(cloud_sag, 0.001));
}


float hfn_layered_clouds(vec2 base_uv, vec2 view_slant, vec2 wind_uv) {
	float base = hfn_cloud_height(base_uv + wind_uv);

	vec2 mid_offset =
		view_slant * cloud_parallax_strength * cloud_parallax_layer_separation
		+ wind_uv * 0.37
		+ vec2(13.71, -8.23);
	float middle = hfn_cloud_height(
		base_uv * cloud_parallax_mid_scale + mid_offset
	);

	vec2 high_offset =
		view_slant * cloud_parallax_strength * cloud_parallax_layer_separation * 1.9
		+ wind_uv * 0.73
		+ vec2(-19.42, 15.31);
	float high = hfn_cloud_height(
		base_uv * cloud_parallax_high_scale + high_offset
	);

	float layered = base;
	layered = mix(
		layered,
		max(base * 0.78, middle),
		cloud_parallax_detail_weight * 0.62
	);
	layered = mix(
		layered,
		clamp(layered * 0.86 + high * 0.22, 0.0, 1.0),
		cloud_parallax_detail_weight * 0.48
	);
	return clamp(layered, 0.0, 1.0);
}


float hfn_cloud_beer(float absorption, float distance_through_cloud) {
	return exp(-absorption * max(distance_through_cloud, 0.0));
}


vec3 hfn_cloud_light(vec3 sun_direction) {
	if (LIGHT0_ENABLED) {
		float light_elevation = max(LIGHT0_DIRECTION.y, 0.0);
		return LIGHT0_COLOR * LIGHT0_ENERGY * light_elevation * cloud_light_energy_scale;
	}
	float solar_elevation = max(sun_direction.y, 0.0);
	return cloud_sun_color.rgb * cloud_sun_energy * solar_elevation * cloud_light_energy_scale;
}


vec3 hfn_apply_parallax_clouds(vec3 atmosphere_color, vec3 sun_direction, vec3 eye_direction) {
	if (eye_direction.y <= 0.005) {
		return atmosphere_color;
	}

	float t = hfn_cloud_plane_intersection(eye_direction);
	if (t < 0.0) {
		return atmosphere_color;
	}

	vec2 wind_uv = cloud_wind_speed * cloud_time * 0.1;
	vec3 tiling = vec3(cloud_noise_tiling.x, 1.0, cloud_noise_tiling.y) * 0.2;
	vec3 cloud_position = eye_direction * t * tiling;

	float safe_up = max(eye_direction.y, 0.08);
	vec2 view_slant = eye_direction.xz / safe_up;
	float cloud_height = hfn_layered_clouds(
		cloud_position.xz,
		view_slant,
		wind_uv
	);

	vec3 depth_position =
		cloud_position + eye_direction * cloud_height * cloud_depth * 0.12;
	float depth_height = hfn_layered_clouds(
		depth_position.xz,
		view_slant * 1.08,
		wind_uv * 1.05
	);
	cloud_height = mix(cloud_height, depth_height, 0.42);

	float cloud_mask = smoothstep(cloud_coverage, max(cloud_mask_top, cloud_coverage + 0.02), cloud_height);
	float view_up = clamp(eye_direction.y, 0.0, 1.0);
	float transmission = hfn_cloud_beer(
		cloud_density,
		1.0 - cloud_height * view_up
	);

	float shape = smoothstep(0.18, 0.82, cloud_height);
	vec3 light_color = hfn_cloud_light(sun_direction);
	vec3 cloud_shadow = cloud_color.rgb * (1.0 - cloud_shadow_strength);
	vec3 cloud_lit = cloud_color.rgb * (1.0 + cloud_shape_contrast * 0.34);

	/* Let Freeman's Rayleigh/Mie color bleed into thin cloud edges. */
	float atmosphere_bleed = 0.10 + (1.0 - shape) * 0.18;
	cloud_lit = mix(cloud_lit, atmosphere_color, atmosphere_bleed);

	float rim = pow(
		clamp(1.0 - abs(cloud_height - 0.48) * 2.0, 0.0, 1.0),
		2.0
	);
	cloud_lit += light_color * transmission * (0.035 + rim * 0.045);

	vec3 cloud_rgb = mix(cloud_lit, cloud_shadow, shape * 0.72);
	if (cloud_top_light > 0.0) {
		/* Directional self-shadow, the usual 2D cloud lighting trick: one more height sample toward the light.
		Where the deck thickens toward the light this side is in its shade (belly); the other side is the lit top. */
		vec2 toward_light = normalize(sun_direction.xz + vec2(0.0001, 0.0));
		float light_side = hfn_layered_clouds(cloud_position.xz + toward_light * 0.035, view_slant, wind_uv);
		float self_shadow = clamp((light_side - cloud_height) * 4.0, 0.0, 1.0);
		vec3 top_tone = max(mix(atmosphere_color, vec3(1.0), 0.6) + light_color * 0.02, cloud_color.rgb * 1.6);
		vec3 volume_rgb = mix(top_tone, cloud_shadow, clamp(self_shadow + shape * 0.15, 0.0, 1.0));
		cloud_rgb = mix(cloud_rgb, volume_rgb, cloud_top_light);
	}
	float horizon_factor = 1.0 - smoothstep(0.02, 0.30, eye_direction.y);
	cloud_rgb = mix(cloud_rgb, atmosphere_color, horizon_factor * 0.12);

	float alpha = clamp(cloud_mask * cloud_opacity, 0.0, 0.94);
	return mix(atmosphere_color, cloud_rgb, alpha);
}


/*
Main integrator for the sky.
Renders the atmosphere, the sun disk and the planet.
*/
group_uniforms PreviewFallback;
uniform bool use_manual_sun_direction = false;
uniform vec3 manual_sun_direction = vec3(0.0, 1.0, 0.0);

void sky() {
	if (!AT_CUBEMAP_PASS && !AT_HALF_RES_PASS) {
		COLOR = HALF_RES_COLOR.rgb;
	} else {
		int view_sample_count = AT_CUBEMAP_PASS ? max(2, view_samples / 4) : view_samples;
		int sun_sample_count = AT_CUBEMAP_PASS ? max(1, sun_samples / 2) : sun_samples;
		vec3 final_color = vec3(0.0);
		vec3 sun_direction = normalize(manual_sun_direction);
		bool sun_available = use_manual_sun_direction;
		if (LIGHT0_ENABLED && !use_manual_sun_direction) {
			sun_direction = LIGHT0_DIRECTION;
			sun_available = true;
		}
	
	// Preserve upstream behavior in game; CI may provide a manual direction.
		if (sun_available) {
		
		float atmosphere_radius = get_atmosphere_radius();
		
		// Position clamped to prevent entering the "low precision zone"
		vec3 ray_origin = vec3(0.0, planet_radius + clamp(POSITION.y + base_altitude, 0.5, atmosphere_height), 0.0);
		vec3 ray_direction = EYEDIR;
		
		// Atmosphere intersection.
		vec2 atmosphere_hit = ray_sphere_intersection(ray_origin, ray_direction, atmosphere_radius);
		
		// Ground intersection.
		vec2 ground_hit = ray_sphere_intersection(ray_origin, ray_direction, planet_radius);	
		bool hits_ground = ground_hit.y > 0.0;
		
		// Clamp the atmosphere to the ocean.
		float atmosphere_distance = hits_ground ? ground_hit.x : atmosphere_hit.y;
		
		// Use half the samples for view to ground, and the other half from ground back to sky.
		int samples = hits_ground ? view_sample_count / 2 : view_sample_count;
		
		// atmosphere radiance.
		vec3 atmosphere_radiance = integrate_radiance(ray_origin, ray_direction, atmosphere_distance, samples, sun_sample_count, sun_direction);
		
		final_color = atmosphere_radiance;
		
		vec3 sun_transmittance = vec3(0.0);
		
		// ground color.
		if (hits_ground) {
			vec3 ground_point = ray_origin + ray_direction * atmosphere_distance;
			vec3 ground_normal = normalize(ground_point);
			
			// how similar are the ray and sun directions.
			float cos_theta = dot(ray_direction, sun_direction);
			
			float ground_to_atmosphere_distance = ray_sphere_intersection(ground_point, ground_normal, atmosphere_radius).y;
			
			// Distance to cover by each step.
			float step_length = ground_to_atmosphere_distance / float(samples);
			
			// Accumulators
			vec3 accumulated_optical_depth = vec3(0.0);
			vec3 accumulated_radiance = vec3(0.0);
			
			//Optical depth at the beginning of the first sample.
			vec3 optical_depth_start = get_optical_depth_at_point(ground_point);
			
			float multi_scattering_mie_phase = get_mie_phase(cos_theta, multiscattering_mie_g_backward, multiscattering_mie_g_forward, multiscattering_mie_weight);
			
			for (int i = 0; i < samples; i++) {
				// Optical deph at the end of the sample.
				vec3 optical_depth_end = get_optical_depth_at_point(ground_point + ground_normal * float(i + 1) * step_length);
				
				// Average them. Jitter changes the weight of the average.
				vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
				
				// Accumulate the optical depth for this step
				accumulated_optical_depth += step_optical_depth;
				
				// I'm not quite sure the jitter belongs here too.
				vec3 sample_point = ground_point + ground_normal * (float(i) + 0.5) * step_length;
				
				// Calculate transmittance.
				vec3 transmittance = exp(-(
					get_rayleigh_scattering() * accumulated_optical_depth.x +
					get_mie_extinction()       * accumulated_optical_depth.y +
					ozone_extinction           * accumulated_optical_depth.z
					));
				
				// Multi scattering approximations.
				vec3 rayleigh_ambient = step_optical_depth.x * get_rayleigh_scattering() * rayleigh_multi_scattering;
				
				//NOTE: Mie multi scattering is not isotropic. If we add it to the planet, we could see the sun through it.
				
				// Accumulate ambient light.
				accumulated_radiance += rayleigh_ambient * transmittance;
				
				// Recycle this end point as the next iteration start point.
				optical_depth_start = optical_depth_end;
			}
			
			// Simple lighting model for the planet.
			float direct_light = max(dot(ground_normal, sun_direction), 0.0);
			
			if (direct_light > 0.0){
				float ground_to_sun_distance = ray_sphere_intersection(ground_point, sun_direction, atmosphere_radius).y;
				sun_transmittance = get_transmittance(ground_point, sun_direction, ground_to_sun_distance, sun_sample_count);
			}
			
			//HACK: An ambient level high enough to illuminate the ground will blow the sky. So we make the same unit affect the ground harder.
			vec3 ground_albedo = ground_color * (direct_light * sun_intensity * sun_transmittance + accumulated_radiance *  75.) * 1.0/PI;
			vec3 transmittance_to_eye = get_transmittance(ray_origin, ray_direction, atmosphere_distance, view_sample_count);
			
			final_color += ground_albedo * transmittance_to_eye;
		}
		}
		if (!AT_CUBEMAP_PASS) {
			final_color = hfn_apply_parallax_clouds(final_color, sun_direction, EYEDIR);
		}
		COLOR = final_color * exposure;
		if (AT_HALF_RES_PASS) {
			ALPHA = 1.0;
		}
	}
}
