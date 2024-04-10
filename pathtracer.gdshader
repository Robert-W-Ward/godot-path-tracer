shader_type canvas_item;
const vec3 BACKGROUND = vec3(0.5);
const int MAX_SPHERES = 4;
const int SAMPLES_PER_PIXEL = 32;
const int MAX_BOUNCES = 100;
#define LAMBERTIAN 0
#define METALLIC 1
#define DIELECTRIC 2
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
	int type; // 0 - Lambertian, 1 - Metallic, 2 - Dielectric
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
	vec2(5,5),
	vec4(1.0,1.0,1.0,100.0)
	);
const PointLight PointLights[4]  = PointLight[](
	PointLight(vec3(0.0,0.0,-2.0),vec4(1.0,1.0,1.0,5.0)),
	PointLight(vec3(-2.0,-3.0,0.0),vec4(1.0,1.0,1.0,5.0)),
	PointLight(vec3(2.0,-3.0,0.0),vec4(1.0,1.0,1.0,5.0)),
	PointLight(vec3(0.0,-3.0,0.0),vec4(1.0,1.0,1.0,5.0))
	
);
const Sphere spheres[4] = Sphere[](
	Sphere(vec3(0, 8, 0),7.0,0),
	Sphere(vec3(-1.8, 0, -1), 0.5, 1),   // Lambertian
	Sphere(vec3(0.0, 0, 0), 0.5, 2),   // Metal
	Sphere(vec3(2, 0, 0), 0.5, 3)   // Dielectric
);
const Material materials[4] = Material[](
	// id,type,roughness,metallic,ior,color,specular,shininess
	Material(0,LAMBERTIAN,0.0,0.0,1.0,vec4(1.0,1.0,1.0,1.0),vec4(1.0,1.0,1.0,0.0),1.0), // White lambertian material
	Material(1,LAMBERTIAN,0.0,0.0,1.0,vec4(0.0,1.0,0.0,1.0),vec4(1.0,1.0,1.0,1.0),10.0), // Green lambertian material
	Material(2,METALLIC,.1,1.0,1.0,vec4(.0,.0,1.0,1.0),vec4(1.0,1.0,1.0,0.0),1.0), // Blue Metallic material
	Material(3,DIELECTRIC,0.6,1.0,1.5,vec4(1.0,0.0,0.0,1.0),vec4(1.0,1.0,1.0,0.1),0.0)  // Red Dielectric material 
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

vec3 SampleGGX(vec2 Xi, vec3 N, float roughness) {
	float a = roughness * roughness;

	// Transform Xi (a uniform random sample) into a sample on the hemisphere
	float theta = atan(a * sqrt(Xi.x) / sqrt(1.0 - Xi.x));
	float phi = 2.0 * PI * Xi.y;

	// Spherical to Cartesian (assuming Y up)
	vec3 H;
	H.x = sin(theta) * cos(phi);
	H.y = cos(theta);
	H.z = sin(theta) * sin(phi);

	// Transform H to be centered around N
	vec3 upVector = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(upVector, N));
	vec3 bitangent = cross(N, tangent);

	// Tangent space to world space
	vec3 sampleVec = H.x * tangent + H.y * N + H.z * bitangent;

	return normalize(sampleVec);
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

vec3 SampleAreaLight(vec3 P,out vec3 L, out float dist){
	float u = random(FragCoord.xy + areaLight.position.xy) - 0.5;
	float v = random(FragCoord.xy + areaLight.position.xy) - 0.5;
	
	vec3 lightRight = cross(areaLight.normal, areaLight.up);
	
	vec3 samplePos = areaLight.position + areaLight.up * (v*areaLight.size.y) + lightRight * (u * areaLight.size.x);
	
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
	float tMax = 10000.0;

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
vec3 CookTorranceSpecularReflectanceBRDF(vec3 L, vec3 V, vec3 N, Material mat, vec3 F0) {
	vec3 H = normalize(V + L);
	float D = DistributionGGX(N, H, mat.roughness);
	vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
	float G = GeometrySmith(N, V, L, mat.roughness);

	float NoL = max(dot(N, L), 0.0);
	float NoV = max(dot(N, V), 0.0);

	vec3 numerator = D * F * G;
	float denominator = 4.0 * NoL * NoV + .0001; // Preventing division by zero
	vec3 specular = numerator / denominator;
	return specular ;
}
vec3 TransmittanceBRDF(vec3 V, vec3 N, vec3 L, Material mat, vec3 F0) {
	// Make this just a BTDF
    vec3 H = normalize(V + L);
    float D = DistributionGGX(N, H, mat.roughness);
    vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
    float G = GeometrySmith(N, V, L, mat.roughness);
    // Calculate reflection component using the BRDF formula
    float NoL = max(dot(N, L), 0.0); // Ensure NoL is non-negative
    float NoV = max(dot(N, V), 0.0); // Ensure NoV is non-negative


    // Calculate transmission component using BTDF, adjusted for non-metallic materials
    vec3 transmission = vec3(0.0);
    if (mat.metallic <= 0.0) { // Only non-metallic materials transmit light
        // Incorporate the TransmittanceBTDF calculation directly
        float eta = mat.ior; // Index of Refraction for the material
        vec3 T = 1.0 - F; // Transmission Fresnel term
        float denom = 4.0 * NoL * NoV;
        if (denom > 0.0) { // Ensure valid denominator
            transmission = (T * D * G) / denom;
        }
    }
    vec3 combined =vec3(1.0); transmission;

    return combined;
}
vec3 TransmittanceBTDF(vec3 V, vec3 N, vec3 L, Material mat, vec3 F0) {
    // V is the view direction
    // L is the light direction (for the transmitted ray, this would be the direction of the refracted ray)
    // N is the surface normal
    // mat is the material properties
    // F0 is the reflectance at normal incidence

    // Only consider transmission for non-metallic materials
    if (mat.metallic > 0.0) {
        return vec3(0.0); // No transmission for metallic materials
    }

    // Compute the half vector between V and L
    vec3 H = normalize(V + L);

    // Calculate the Fresnel term using Schlick's approximation
    float cosTheta = max(dot(N, -V), 0.0); // Using -V since V points toward the viewer
    vec3 F = FresnelSchlick(cosTheta, F0);

    // Calculate the D term (GGX normal distribution)
    float D = DistributionGGX(N, H, mat.roughness);

    // Calculate the geometry term G
    float G = GeometrySmith(N, V, L, mat.roughness);

    // Compute the amount of light not reflected (i.e., transmitted)
    vec3 T = 1.0 - F; 

    // Snell's law to find the transmitted direction, ensuring that V is negated since it points toward the viewer
    vec3 transmittedDir = refract(-V, N, 1.0 / mat.ior);

    // Calculate the transmitted component (we need to take the absolute value of dot products)
    float NoL = abs(dot(N, L)); // Abs since we are dealing with transmitted light
    float NoV = abs(dot(N, -V)); // Abs for the same reason as above

    // Compute the transmitted light contribution
    vec3 transmission = vec3(0.0);
    if (NoL > 0.0 && NoV > 0.0) {
        // Calculate the denominator of the BTDF (the 4.0 * NoL * NoV term comes from the microfacet BRDF derivation)
        float eta = mat.ior; // Index of Refraction for the material
        float eta2 = eta * eta; // Square of the IOR
        float denom = 4.0 * NoL * NoV;

        // Fresnel term adjusted for transmission
        vec3 Ft = F * eta2;

        // BTDF formula
        transmission = (1.0 - Ft) * D * G / denom;
    }

    // Return the transmitted light (BTDF value)
    return transmission * NoL; // Multiply by NoL to account for Lambert's cosine law
}
bool CastsShadow(Ray shadowRay, Hit shadowHit,float distToLight){
	RayIntersect(shadowRay,shadowHit);
	if(shadowHit.dist> 0.0 && shadowHit.dist < distToLight){
		return true;
	}else return false;
}
vec3 CalcAreaLightContrib(vec3 P,vec3 N,vec3 V,vec3 F0,Material mat){
	int numSamples = 4;
	vec3 AreaLightContrib = vec3(0.0);
	float distanceToLight = 0.0;
	vec3 L = normalize(areaLight.position - P); // default it to the center of the area light
	vec3 samplePos = SampleAreaLight(P,L,distanceToLight); // sample the center first
 	float attenuation = 1.0 / (distanceToLight * distanceToLight);
	vec3 BRDF = vec3(0.0);
	Ray shadowRay;
	shadowRay.origin = P + N * 0.001;
	shadowRay.direction = L;
	Hit shadowHit;
	float NoL = max(dot(N, L), 0.0);
	for(int s = 0; s < numSamples; ++s){
		if(!CastsShadow(shadowRay,shadowHit,distanceToLight)){
			switch(mat.type){
			case LAMBERTIAN:
				vec3 diffuse = LambertianReflectanceBRDF(L,N,mat.color.rgb,1.0);
				vec3 specular = PhongSpecularReflectanceBRDF(L,N,V,mat.specular.rgb,mat.shininess,mat.specular.a);
				BRDF = diffuse + specular;
				AreaLightContrib += areaLight.color.w * BRDF * NoL * attenuation;
				break;
			case METALLIC:
				vec3 BRDF = CookTorranceSpecularReflectanceBRDF(L,V,N,mat, F0);
				AreaLightContrib += areaLight.color.w * BRDF * attenuation;
				break;
			case DIELECTRIC:
				// Dielectric Cook Torrance
				F0 = vec3(0.04); // Base reflectivity for dielectrics
				vec3 transmittance = TransmittanceBTDF(V,N,L,mat, F0);
				vec3 directTransmittance =  areaLight.color.rgb * transmittance * NoL * attenuation;
				//BRDF = CookTorranceSpecularReflectanceBRDF(L,V,N,mat, F0);
				AreaLightContrib += directTransmittance;
				break;
			default:
				break;
			}
		}
		AreaLightContrib /= float(numSamples);
	}
	AreaLightContrib /= float(numSamples);
	return AreaLightContrib;
}
vec3 CalcPointLightContrib(vec3 P,vec3 N,vec3 V,vec3 F0,Material mat){
	vec3 PointLightContrib = vec3(0.0);
	for(int i = 0; i< PointLights.length(); ++i){
		PointLight light = PointLights[i];
		vec3 L = normalize(light.position - P);
		float distanceToLight = length(light.position - P);
		vec3 H = normalize(V+L);
		float attenuation = 1.0 / (distanceToLight * distanceToLight);
		float NoL = max(dot(N,L),0.0);
		vec3 F = FresnelSchlick(dot(H,V),F0);
		vec3 BRDF;
		Ray shadowRay;
		shadowRay.origin = P + N * 0.001;
		shadowRay.direction = L;
		Hit shadowHit;
		if(!CastsShadow(shadowRay,shadowHit,distanceToLight)){
			switch(mat.type){
				case LAMBERTIAN:
					// Lambetian + Phong
					vec3 diffuse = LambertianReflectanceBRDF(L,N,mat.color.rgb,1.0);
					vec3 specular = PhongSpecularReflectanceBRDF(L,N,V,mat.specular.rgb,mat.shininess,mat.specular.w);
					BRDF = diffuse + specular;
					PointLightContrib += light.color.w * BRDF * NoL * attenuation;
					break;
				case METALLIC:
					PointLightContrib += CookTorranceSpecularReflectanceBRDF(L,V,N,mat,F0) * light.color.w * attenuation;	
					break;
				case DIELECTRIC:
					// Dielectric CookTorrance
					vec3 specular = CookTorranceSpecularReflectanceBRDF(L,V,N,mat,F0);
					vec3 transmission = TransmittanceBTDF(V,N,L,mat,F0);
					vec3 reflectedLight = specular * light.color.rgb * attenuation;
					vec3 transmittedLight = transmission * light.color.rgb * attenuation *  (1.0-F);
                	PointLightContrib +=  reflectedLight + transmittedLight;
					break;
			}
		}
	}
	return PointLightContrib;
}
vec3 CalculateDirectLighting(vec3 P, vec3 N,vec3 V,vec3 F0,Material mat){
	vec3 directLight = vec3(0.0);
	// Sample the Area light first
	directLight += CalcAreaLightContrib(P,N,V,F0,mat);
	// Then do point lights
	directLight += CalcPointLightContrib(P,N,V,F0,mat);
	return directLight;
}
void swap(out float A, out float B){
	float t = A;
	A = B;
	B = A;
}
vec3 TracePath(Ray ray){
	vec3 throughput = vec3(1.0);
	vec3 radiance = vec3(0.0);
	//D_0 + T_0 * L_0 * ( D_1 + L_1 * (D_2 + L_2....
	// For each ray
	// If the depth is >= to the maximum depth, terminate
	for(int i = 0; i < MAX_BOUNCES; ++i){
		Hit hit;
		// Find nearest object
		RayIntersect(ray,hit);
		//Russian roulette termination
		if(i > 3){
			float p = (throughput.x + throughput.y + throughput.z)/3.0;
			if(random(FragCoord.xy) + float(i)> p){
				break;
			}
			throughput/=p;
		}
		
		if(hit.dist<= 0.0)// Don't hit anything return background
 			return radiance += throughput * BACKGROUND;
		
		Material mat = materials[hit.materialId]; // hit surfaces material
		vec3 N = normalize(hit.normal); // Normalized Normal
		vec3 V = -ray.direction; // Direction of the viewer/eye
		vec3 P = hit.point; // Point that was hit
		vec3 F0 = mix(vec3(0.04),mat.color.rgb,mat.metallic);
		vec3 directLight = CalculateDirectLighting(P,N,V,F0,mat); // Calculate direct lighting for this hit
		radiance +=  throughput * directLight; // If doing direct lighting sample a light and add its comtribution	
		
		vec3 newDir;
		float pdf = 1.0;
		vec3 BRDF = vec3(1.0);
		float cosTheta = 1.0;

		//Indirect Lighting
		switch(mat.type){
			case LAMBERTIAN:
				newDir = SampleHemisphere(N); // Cosine weighted hemisphere sampling
				cosTheta = max(dot(N,newDir),0.0); //  
				BRDF = LambertianReflectanceBRDF(newDir,V,mat.color.rgb,1.0);
				pdf = cosTheta/(1.0*PI); // Uniform distribution over the hemisphere
				throughput *= BRDF * cosTheta /pdf;
				ray.direction = newDir;
				ray.origin = P + N * 0.001;
				break;
			case METALLIC:
				// V = -ray.direction
				// OpenGL reflect and refract functions expect the "incident" vector i.e. ray.direction not -ray.direction
				vec2 Xi = vec2(random(P.xy),random(P.xy));
				vec3 H = SampleGGX(Xi,N,mat.roughness);// For hit surface determine the next dir w_i by sampling
				newDir = reflect(-V,H);
				cosTheta = max(dot(N,newDir),0.0);
				// Q1: Why is it black when perfectly reflective i.e. roughness = 0.0 A: The math breaks down at really low roughness
				BRDF = CookTorranceSpecularReflectanceBRDF(newDir,V,N,mat,F0); // Determine color/reflectance
			    pdf = DistributionGGX(N, H, mat.roughness) * max(dot(N, H), 0.0) / (4.0 * abs(dot(H, V)));
				throughput *=  BRDF * cosTheta/pdf;
				ray.direction = newDir;
				ray.origin = P + N * 0.001;
				break;
			case DIELECTRIC:
				// Assuming roughness is defined in your material structure: mat.roughness
				vec3 H;
				// Sample microfacet normal H based on GGX distribution and surface roughness
				vec2 Xi = vec2(random(P.xy), random(P.xy)); // Random sample for GGX
				H = SampleGGX(Xi, N, mat.roughness); // Sample GGX based on roughness and normal

				float cosTheta = max(dot(-V, N), 0.0);
				vec3 F = FresnelSchlick(max(dot(H, V), 0.0), F0); // Use microfacet normal for Fresnel

				// Decide on reflection or refraction
				float R = random(P.xy);
				float F_avg = (F.x + F.y + F.z) / 3.0;
				bool shouldReflect = R < F_avg;

				if (shouldReflect) {
				    // Reflect based on microfacet normal
				    newDir = reflect(-V, H); // Note: Reflecting off H rather than N
				    BRDF = CookTorranceSpecularReflectanceBRDF(newDir,H, N, mat, F0); // Adjusted for H
				    ray.direction = newDir;
				    ray.origin = P + N * 0.001;
				} else {
					float etaI = 1.0;
					float etaT = mat.ior;
					if(dot(V,N)>0.0){
						swap(etaI,etaT);
						N = -N;
					}
					float eta = etaI/etaT;
					float cosThetaI = dot(-V,N);
					float sinThetaI2 = max(0.0,1.0-cosThetaI * cosThetaI);
					float sinThetaT2 = eta * eta* sinThetaI2;
					if(sinThetaT2>1.0){ // TIR
						newDir = reflect(V,N); // relfect instead
					}else{
						float cosThetaT = sqrt(max(0.0,1.0 - sinThetaT2));
						vec3 refractDir = normalize(eta*-V + (eta*cosThetaI - cosThetaT)*N);
						vec3 H = normalize(V+refractDir);
						newDir = refract(-V,H,eta);
						if(length(newDir) == 0.0){
							newDir = reflect(V,N);//Fallback
						}
					}
					BRDF = TransmittanceBTDF(V,N,newDir,mat,F0);
					ray.direction = newDir;
					ray.origin = P + N * 0.001;
					throughput *= BRDF;
				}
				break;
			default:
				break;
			}
		if(length(throughput)<0.001){
			return radiance;
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

    // fPersp controls the camera's field of view.
    float fPersp = 2.0;
	vec3 vDir = normalize(uv.x * camRight + uv.y * camUp + camForward * fPersp);

	return vDir;
}
// For each pixel
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
	// For each sample
	for(int y = 0;y<sqrtSamples;++y){
		for(int x = 0; x < sqrtSamples;++x){
			float jitterX = random(uv) * stratumSize.x;
			float jitterY = random(uv) * stratumSize.y;
			vec2 jitteredUV = uv + vec2(float(x) / float(sqrtSamples) - 0.5 + jitterX, float(y) / float(sqrtSamples) - 0.5 + jitterY) / Resolution;
			// Generate a ray from eye to random pt w/in pixel with zero color
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