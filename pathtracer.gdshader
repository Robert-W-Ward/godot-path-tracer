shader_type canvas_item;
const vec3 BACKGROUND = vec3(0.5);
const int MAX_SPHERES = 4;
const int SAMPLES_PER_PIXEL = 4;
const int MAX_BOUNCES = 10;
varying vec4 FragCoord;
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
	vec4 specular; // for Phong specular xyz: color w: intensity
	float shininess; // for Phon specular
};

struct PointLight{
	vec3 position;
	vec4 color; //xyz color, w for intensity
};

struct AreaLight{
	vec3 position;
	vec3 normal;
	vec3 up;
	vec2 size;
	vec4 color;
};
const AreaLight areaLight = AreaLight(
	vec3(0.0,-3.0,0.0),
	vec3(0.0,-1.0,0.0),
	vec3(0.0,0.0,1.0),
	vec2(4,4),
	vec4(1.0,1.0,1.0,0.0)
	);
const PointLight PointLights[3]  = PointLight[](
	PointLight(vec3(0.0,-3.0,0.0),vec4(1.0,1.0,1.0,1.0)),
	PointLight(vec3(-2.0,-3.0,0.0),vec4(1.0,1.0,1.0,1.0)),
	PointLight(vec3(2.0,-3.0,0.0),vec4(1.0,1.0,1.0,1.0))
);
const Material materials[4] = Material[](
	Material(0,1,0.5,0.8,0.0,vec4(1.0,1.0,1.0,1.0),vec4(1.0,1.0,1.0,1.0),.2), // White lambertian material
	Material(1,0,0.0,0.0,0.0,vec4(0.0,1.0,0.0,1.0),vec4(1.0,1.0,1.0,0.5),.2), // Green lambertian material
	Material(2,1,0.5,1.0,1.0,vec4(0.0,0.0,1.0,1.0),vec4(1.0,1.0,1.0,1.0),.2), // Blue Metallic material
	Material(3,2,1.0,0.0,1.5,vec4(1.0,0.0,0.0,1.0),vec4(1.0,1.0,1.0,1.0),.2)  // Red Dielectric material 
);

const Sphere spheres[4] = Sphere[](
	Sphere(vec3(0, 6, 0),5.0,0),
	Sphere(vec3(-2, 0, 0), 0.5, 1),   // Lambertian
	Sphere(vec3(0, 0, 0), 0.5, 2),   // Metal
	Sphere(vec3(2, 0, 0), 0.5, 3)   // Dielectric
);

float random(vec2 st){
    return fract(sin(dot(st.xy, vec2(12.9898,78.233)))* 43758.5453123);
}

vec3 FresnelSchlick(float cosTheta, vec3 F0){
	return F0 + (1.0 - F0) * pow(1.0-cosTheta,5.0);
}

float DistributionGGX(vec3 N, vec3 H, float roughness){
	float a = roughness*roughness;
	float a2 = a*a;
	float NoH = max(dot(N,H),0.0);
	float NoH2 = (NoH*NoH);
	
	float numerator = a2;
	float denom = (NoH2 * (a2-1.0)+1.0);
	denom = 3.14159 * denom * denom;
	
	return numerator / denom;
}

float GeometrySchlickGGX(float NoV, float roughness){
	float r = (roughness + 1.0);
	float k = (r*r) / 8.0;
	float num = NoV;
	float denom = NoV * (1.0 - k) +k;
	return num /denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness){
	float NoV = max(dot(N,V),0.0);
	float NoL = max(dot(N,L),0.0);
	float ggx1 = GeometrySchlickGGX(NoV,roughness);
	float ggx2 = GeometrySchlickGGX(NoL,roughness);
	return ggx1 * ggx2;
}

vec3 SampleHemisphere(vec3 N){
	float r1 = random(N.xy);
	float r2 = random(N.xy);
	float theta = 2.0 * PI * r1;
	float phi = acos(sqrt(1.0-r2));
	
	//Sphereical to Catersian Conversion
	vec3 direction;
	direction.x = sin(phi) * cos(theta);
	direction.y = sin(phi) * sin(theta);
	direction.z = cos(phi);
	
	// Construct local coordinates
	vec3 w = N;
	vec3 a = (abs(w.x) >0.9)? vec3(0,1,0): vec3(1,0,0);
	vec3 u = normalize(cross(a,w));
	vec3 v = cross(w,u);
	
	return direction.x * u + direction.y * v + direction.z * w;
}
vec3 SampleAreaLight(vec3 P, AreaLight light,out vec3 L, out float dist){
	float u = random(FragCoord.xy + light.position.xy) - 0.5;
	float v = random(FragCoord.xy + light.position.xy) - 0.5;
	
	vec3 lightRight = cross(light.normal, light.up);
	
	vec3 samplePos = light.position + light.up * (v*light.size.y) + lightRight * (u * light.size.x);
	
	L = normalize(samplePos - P);
	dist = length(samplePos -P);
	return samplePos;
}

float SphereSDF(vec3 p, vec3 center,float radius){
	return length(p-center) - radius;	
}
float SceneSDF(vec3 p, out int matId){
	float minDist = 1e9;
	float dist = 1e9;
	for(int i = 0;i<spheres.length();++i){
		int m;
		Sphere sphere = spheres[i];
		m = sphere.material;
		dist = SphereSDF(p,sphere.center,sphere.radius);
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
vec3 PhongSpecularReflectanceBRDF(vec3 L, vec3 N, vec3 V, vec3 specularColor, float shininess, float intensity){
	vec3 R = reflect(-L,N);
	float specularAngle = max(dot(V,R),0.0);
	return specularColor * intensity * pow(specularAngle,shininess);
}

vec3 CookTorranceBRDF(vec3 L, vec3 V, vec3 N, Material mat, vec3 F0) {
    vec3 H = normalize(V + L);
    float D = DistributionGGX(N, H, mat.roughness);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    float G = GeometrySmith(N, V, L, mat.roughness);

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);

    vec3 numerator = D * F * G;
    float denominator = 4.0 * NdotL * NdotV + 0.001; // Preventing division by zero
    vec3 specular = numerator / denominator;

    // Combining specular and diffuse reflectance
    vec3 kD = vec3(1.0) - F; // This is for non-metals, for metals it will be zero
    kD *= 1.0 - mat.metallic; // Completely specular for metals

    vec3 diffuse = (1.0 - mat.metallic) * mat.color.rgb / PI;

    return (kD * diffuse + specular) * NdotL; // This already includes Lambertian part for non-metallic
}

bool inShadow(Ray shadowRay, Hit shadowHit,float distToLight){
	RayIntersect(shadowRay,shadowHit);
	if(shadowHit.dist> 0.0 && shadowHit.dist < distToLight){
		return false;
	}else return true;
}

vec3 CalculateDirectLighting(vec3 P, vec3 N,vec3 V,Material mat,AreaLight al){
	vec3 dirLight = vec3(0.0);
	vec3 L = vec3(0.0);
	float distanceToLight = 0.0;
	float attenuation = 0.0;
	Ray shadowRay;
	Hit shadowHit;
	vec3 F0 = mix(vec3(0.04),mat.color.rgb,mat.metallic);
	// Sample the Area light first
	for(int s =0 ;s<5;++s){
		vec3 samplePos = SampleAreaLight(P,areaLight,L,distanceToLight);
	 	attenuation = 1.0/(distanceToLight * distanceToLight);
		// Shadow for area light
		shadowRay.origin = P + N * 0.001;
		shadowRay.direction = L;
		float NoL = max(dot(N, L), 0.0);

		if (inShadow(shadowRay,shadowHit,distanceToLight)) { // If in shadow
			// Metallics and Dielectrics use cook-torrance
			if(mat.metallic > 0.0){
				dirLight +=  CookTorranceBRDF(L,V,N,mat, F0) ;
			}else{
				vec3 diffuse = LambertianReflectanceBRDF(L, N, mat.color.rgb, 1.0);
				vec3 specular = PhongSpecularReflectanceBRDF(L, N, V, mat.specular.rgb, mat.shininess, mat.specular.w);
				vec3 BRDF = diffuse + specular;
				dirLight += areaLight.color.w * BRDF * NoL * attenuation;
			}
			
		}
	}
	dirLight /= float(5);
	vec3 BRDF = vec3(0.0);
	for(int i = 0; i< PointLights.length(); ++i){
		PointLight light = PointLights[i];
		L = normalize(light.position - P);
		distanceToLight = length(light.position - P);
		attenuation = 1.0/(distanceToLight * distanceToLight);
		float NoL = max(dot(N,L),0.0);
		
		shadowRay.origin = P + N * 0.001;
		shadowRay.direction = L;
		shadowHit;
		if(inShadow(shadowRay,shadowHit,distanceToLight)){
			if (mat.metallic > 0.0){
				dirLight += CookTorranceBRDF(L,V,N,mat,F0);	
			}else{
				vec3 diffuse = LambertianReflectanceBRDF(L,N,mat.color.rgb,1.0);
				vec3 specular = PhongSpecularReflectanceBRDF(L,N,V,mat.specular.rgb,mat.shininess,mat.specular.w);
				BRDF = diffuse + specular;
			}
		dirLight += light.color.w * BRDF * NoL * attenuation;
		}
	}
	return dirLight;
}

vec3 TracePath(Ray ray){
	vec3 throughput = vec3(1.0);
	vec3 radiance = vec3(0.0);
	for(int i = 0; i < MAX_BOUNCES; ++i){
		Hit hit;
		// Find nearest object
		RayIntersect(ray,hit);
		// Don't hit return background
		if(hit.dist<= 0.0)
			return radiance + throughput * BACKGROUND;
		// if hit something get its material
		if(hit.dist>0.0){
			Material mat = materials[hit.materialId];
			vec3 N = normalize(hit.normal);
			vec3 directLight = CalculateDirectLighting(hit.point,N,-ray.direction,mat, areaLight);
			radiance += throughput * directLight;
			
			// Importance sampling using Cosine weighted sampling of the hemisphere
			vec3 L = SampleHemisphere(N);
			vec3 BRDF;
			if(mat.metallic<=0.0){
				BRDF = LambertianReflectanceBRDF(L,N,mat.color.rgb, .5);
			}else{
				vec3 F0 = mix(vec3(0.04), mat.color.rgb, mat.metallic);
				BRDF = CookTorranceBRDF(L,-ray.direction,N,mat,F0);
			}
			// Calculate BRDF for indirect lights
			float LoN = max(dot(L,N),0.0);
			// Contribution of the indirect light to the "Radiance"
			throughput *= BRDF * LoN;
			// Determine how it reflects or refracts
			// TODO: Reflections and Refractions
			// TODO: update rays origin and dir to match relfection or fractions ray
			//  update ray origin and direction for continuation along path
			ray.origin = hit.point + N * 0.001;
			ray.direction = L;
		}
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
	FragCoord = FRAGCOORD;
	vec2 uv = NormalizedScreenCoords(FRAGCOORD.xy,Resolution);
	vec3 camPos = vec3(0,0,-3);
	vec3 at = vec3(0.0);
	vec3 rayDir;
	int sqrtSamples = int(sqrt(float(SAMPLES_PER_PIXEL)));
	vec2 stratumSize = 1.0/vec2(float(sqrtSamples)*Resolution);
	for(int y = 0;y<sqrtSamples;++y){
		for(int x = 0; x < sqrtSamples;++x){
			float jitterX = random(uv) * stratumSize.x;
			float jitterY = random(uv) * stratumSize.y;
			vec2 jitteredUV = uv + vec2(float(x) / float(sqrtSamples) - 0.5 + jitterX, float(y) / float(sqrtSamples) - 0.5 + jitterY) / Resolution;
			rayDir =  GetCameraRayDir(jitteredUV,camPos,at);
			 Ray ray;
			ray.origin = camPos;
			ray.direction = rayDir;
			color += TracePath(ray);
		}
	}
	color /= float(SAMPLES_PER_PIXEL);
	color = sqrt(color); // Gamma correction
    COLOR = vec4(color, 1.0);
}