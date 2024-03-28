shader_type canvas_item;
const vec3 BACKGROUND = vec3(0.5, 0.7, 1.0);
const int MAX_SPHERES = 3;
const int SAMPLES_PER_PIXEL = 32;
const int MAX_BOUNCES = 10;
struct Ray {
    vec3 origin;
    vec3 direction;
};
struct Hit{
    vec3 normal;
    int materialId;
    vec3 point;
    float dist;
};
struct Sphere {
    vec3 center;
    float radius;
    int material;
};
struct Material{
	int id;
	int type;
	float roughness;
	float metallic;
	float ior;
	vec4 color;
};

struct PointLight{
	vec3 position;
	vec3 color;
	float intensity;
};

const Material materials[MAX_SPHERES] = Material[](
	Material(0,0,0.0,0.0,0.0,vec4(0.0,1.0,0.0,1.0)),
	Material(1,1,0.5,1.0,0.0,vec4(0.0,0.0,1.0,1.0)),
	Material(2,2,0.1,0.0,1.5,vec4(1.0,0.0,0.0,1.0))
);

const Sphere spheres[MAX_SPHERES] = Sphere[](
    Sphere(vec3(-2, 0, 0), 0.5, 0),   // Lambertian
    Sphere(vec3(0, 0, 0), 0.5, 1),   // Metal
    Sphere(vec3(2, 0, 0), 0.5, 2)   // Dielectric
);
float random(vec2 st){
    return fract(sin(dot(st.xy, vec2(12.9898,78.233)))* 43758.5453123);
}


float SphereSDF(vec3 p, vec3 center){
	return length(p-center) - 1.0;	
}
float SceneSDF(vec3 p, out int matId){
	float minDist = 1e9;
	float dist = 1e9;
	for(int i = 0;i<spheres.length();++i){
		int m;
		m = spheres[i].material;
		dist = SphereSDF(p,spheres[i].center);
		if(dist< minDist){
			minDist = dist;
			matId = m;
		}
	}
	return minDist;
}
vec3 CalculateNormal(vec3 p, float epsilon) {
    vec3 dx = vec3(epsilon, 0.0, 0.0);
    vec3 dy = vec3(0.0, epsilon, 0.0);
    vec3 dz = vec3(0.0, 0.0, epsilon);
    int m = 0;
    float d = SceneSDF(p,m);
    vec3 n = vec3(
        SceneSDF(p + dx,m) - d,
        SceneSDF(p + dy,m) - d,
        SceneSDF(p + dz,m) - d
    );

    return normalize(n);
}
void RayIntersect(Ray ray,out Hit hit){
	float tMin = 0.001;
	float tMax = 1000.0;

	while(tMin<tMax){
		vec3 p = ray.origin + ray.direction * tMin;
		int matId = 0;
		float dist = SceneSDF(p,matId);
		if(dist < .001){
			hit.dist = dist;
			hit.point = p;
			hit.normal = CalculateNormal(p,0.001);
			hit.materialId = matId;
			return;
		}
		tMin += dist;
	}
	hit.dist = -1.0;
}

vec3 LambertianReflectanceBRDF(vec3 L, vec3 N,vec3 color,float intensity){
	float LoN = dot(L,N) ;
	return LoN * color * intensity/ PI;
}
vec3 TracePath(Ray ray){
	vec3 radiance = vec3(1.0);
	for(int i = 0; i < MAX_BOUNCES; ++i){
		Hit hit;
		// Find nearest object
		RayIntersect(ray,hit);
		// if we hit something
		if(hit.dist>0.0){
			// determine its material
			Material mat = materials[hit.materialId];
			// Calculate BRDF
			vec3 L = vec3(0.0,1.0,1.0);
			vec3 N = normalize(hit.normal);
			vec3 BRDF = LambertianReflectanceBRDF(L,N,mat.color.rgb, .5);
			// Contribution to the "Radiance"
			radiance += BRDF;
			// Determine how it reflects or refracts
			// TODO: Reflections and Refractions
			// update rays origin and dir to match relfection or fractions ray
			// TODO: update ray origin and direction for continuation along path
			// continue loop
		}else{
			radiance = BACKGROUND;
		}
		// else we don't hit anything
		// return background radiance
	}
	
	return radiance;
}
vec2 NormalizedScreenCoords(vec2 screenCoord,vec2 iResolution){
    vec2 result = 2.0 * (screenCoord/iResolution.xy - 0.5);
    result.x *= iResolution.x/iResolution.y; // Correct for aspect ratio
    return result;
}
vec3 GetCameraRayDir(vec2 uv, vec3 camPos, vec3 camTarget){
	vec3 camForward = normalize(camTarget - camPos);
	vec3 camRight = normalize(cross(vec3(0.0, 1.0, 0.0), camForward));
	vec3 camUp = normalize(cross(camForward, camRight));

    // fPersp controls the camera's field of view. Try changing it!
    float fPersp = 2.0;
	vec3 vDir = normalize(uv.x * camRight + uv.y * camUp + camForward * fPersp);

	return vDir;
}
void fragment() {
    vec3 color = vec3(0.0);
	vec2 Resolution = 1.0/SCREEN_PIXEL_SIZE;
	vec2 uv = NormalizedScreenCoords(FRAGCOORD.xy,Resolution);
	vec3 camPos = vec3(0,0,-3);
	vec3 at = vec3(0.0);
	vec3 rayDir = GetCameraRayDir(uv,camPos,at);
    for (int i = 0; i < SAMPLES_PER_PIXEL; i++) {
        Ray ray;
		// TODO: Stratiffied Jittering
		ray.origin = camPos;
		ray.direction = rayDir;
		color += TracePath(ray);
	}
	color /= float(SAMPLES_PER_PIXEL);
	color = sqrt(color); // Gamma correction
    COLOR = vec4(color, 1.0);
}