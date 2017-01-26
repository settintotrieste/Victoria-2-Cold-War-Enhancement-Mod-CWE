float4x4 ViewProjectionMatrix;
float3 CameraPosition;
float4x4 matBones[45] : Bones;
float3 LightDirection;
float3 LightDirection2;
float4 PrimaryColor   = float4(0.8, 0.0, 0, 1);
float4 SecondaryColor = float4(0.7, 0.7, 0, 1);
float4 TextureOffset;

// debug flags
//#define DEBUG_ONLY_SPECULAR
//#define DEBUG_ONLY_DIFFUSE
//#define DEBUG_ONLY_COLORMAP
//#define DEBUG_SHOW_NORMALMAP
//#define DEBUG_SHOW_SPECULARMAP
//#define DEBUG_SHOW_TEXCOORDS

// select lighting model to use
#define LIGHTMODEL_WRAP
//#define LIGHTMODEL_HALFLAMBERT
//#define LIGHTMODEL_PHONG

const int SKINNING_INFLUENCES = 4;

float SpecularPower = 35;
float Specularity = 0.8;
const float WRAP = 0.6;

const float INTENSITY[2] = {1.0, 0.0};
const float3 LIGHT_DIRECTIONS[2] = { float3(0.0, -1.0, 0.5),
                                     float3(-2.0, -1.0, 1)};
const float SAIL_SHINETHROUGH = 0.7;

texture tex0 : DiffuseTexture;
sampler2D DiffuseMap = 
sampler_state 
{
    texture = <tex0>;
    AddressU  = Clamp;        
    AddressV  = Clamp;
    AddressW  = Clamp;
    MipFilter = Linear;
    MagFilter = Linear;
	MinFilter = Anisotropic;
    
    MaxAnisotropy = 4;
};

texture tex1 : SpecularTexture;
sampler2D SpecularMap = 
sampler_state 
{
    texture = <tex1>;
    AddressU  = CLAMP;        
    AddressV  = CLAMP;
    AddressW  = CLAMP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

texture tex2 : NormalTexture;
sampler2D NormalMap = 
sampler_state 
{
    texture = <tex2>;
    AddressU  = CLAMP;        
    AddressV  = CLAMP;
    AddressW  = CLAMP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

texture tex3 : FlagTexture;
sampler2D FlagMap = 
sampler_state 
{
    texture = <tex3>;
    AddressU  = CLAMP;        
    AddressV  = CLAMP;
    AddressW  = CLAMP;
    MIPFILTER = LINEAR;
    MINFILTER = LINEAR;
    MAGFILTER = LINEAR;
};

struct VS_INPUT
{
    float4 vPosition   : POSITION;
    float3 vNormal     : NORMAL;
	float4 vTangent    : TANGENT;
	float2 vTexCoord0  : TEXCOORD0;
	float4 boneIndices : BLENDINDICES;
    float4 boneWeights : BLENDWEIGHT;
};

struct VS_OUTPUT
{
    float4 vPosition  : POSITION;
	float2 vTexCoord0 : TEXCOORD0;
	
	float3 LightDirection : TEXCOORD1;
	float3 LightDirection2 : TEXCOORD2;
	float Specular : TEXCOORD3;
};

float2 GetTexCoordsInFlagAtlas(float2 TexCoord)
{
	const float2 FLAG_MIN = float2(0.92, 0.573);
	const float2 FLAG_MAX = float2(0.214, 1.0);

	// map from flag area to full 0-1 range.
	// its ok since we mask around the actual flag area	
	float2 tc = (TexCoord - FLAG_MIN) / (FLAG_MAX - FLAG_MIN);
			
	return float2( (tc.x / TextureOffset.x) + TextureOffset.z,
	               (tc.y / TextureOffset.y) + TextureOffset.w );
}

VS_OUTPUT SkinnedAvatarVS(const VS_INPUT v )
{
	VS_OUTPUT Out = (VS_OUTPUT)0;
	float3 vLightDirection = normalize( LIGHT_DIRECTIONS[0] );
	float3 vLightDirection2 = normalize( LIGHT_DIRECTIONS[1] );
	
	float4 skinnedPosition = (float4)0;
	float4 skinnedNormal   = (float4)0;
	float4 skinnedTangent  = (float4)0;
	
	float4 vPosition = float4(v.vPosition.xyz, 1.0);

	// skinning
	for( int i = 0; i < SKINNING_INFLUENCES; ++i )
    {
    	float4x4 mat = matBones[ v.boneIndices[i] ];

		float4 offset = mul( vPosition, mat ) * v.boneWeights[i];
		skinnedPosition += offset;
		
		offset = mul( normalize(v.vNormal), mat )  * v.boneWeights[i];
		skinnedNormal += offset;

		offset = mul( normalize(v.vTangent), mat ) * v.boneWeights[i];
		skinnedTangent += offset;
	}
	
	skinnedNormal  = normalize(skinnedNormal);
	skinnedTangent = normalize(skinnedTangent);
	float3 binormal = cross(skinnedTangent.xyz, skinnedNormal.xyz ) * v.vTangent.w;
	normalize(binormal);
	
	// transform light direction into tangent space
	float3x3 matTBN = float3x3(skinnedTangent.xyz, 
	                           binormal,
							   skinnedNormal.xyz);
	Out.LightDirection = mul(matTBN, -vLightDirection);
	Out.LightDirection2 = mul(matTBN, -vLightDirection2);
	
	Out.vPosition = mul(skinnedPosition, ViewProjectionMatrix );
	Out.vTexCoord0 = v.vTexCoord0;
	
	
	const int NLIGHTS = 2;
	Out.Specular = 0;
	float3 LightDirections[NLIGHTS];
	LightDirections[0] = -vLightDirection;
	LightDirections[1] = -vLightDirection2;
	float3 E = mul(matTBN, normalize(skinnedPosition - CameraPosition ));
	for (int i = 0; i < NLIGHTS; ++i)
	{
		float3 H = normalize(E + LightDirections[i]); 				//half angle vector
		Out.Specular += pow( max(0, dot(skinnedNormal.xyz, H) ), SpecularPower ) * Specularity * INTENSITY[i];
	}
	
	return Out;
}

float4 SkinnedAvatarPS( VS_OUTPUT In ) : COLOR
{
	float4 vColor = tex2D( DiffuseMap, In.vTexCoord0 );
	float3 vSpecColor = tex2D( SpecularMap, In.vTexCoord0 ).rgb;
	float4 vFlagColor = tex2D( FlagMap, GetTexCoordsInFlagAtlas(In.vTexCoord0) );
	
	float3 vNormal = normalize( tex2D( NormalMap, In.vTexCoord0 ).rgb * 2.0 - 1 );
		
	// put in special country colors
	// we store where they should be used in the green/blue components of the specular map.
	//vColor.rgb += (PrimaryColor.rgb * vSpecColor.g);

	const int NLIGHTS = 2;
	float3 vLightDirection[NLIGHTS];
	vLightDirection[0] = normalize(In.LightDirection);
	vLightDirection[1] = normalize(In.LightDirection2);
	
	float diffuse = 0.0;
	for (int i = 0; i < NLIGHTS; ++i)
	{
		float  NdotL = max(0, dot( vNormal, vLightDirection[i] ) );
			
		#ifdef LIGHTMODEL_WRAP
		diffuse += saturate((NdotL + WRAP) / (1 + WRAP)) * INTENSITY[i];
		#endif
		#ifdef LIGHTMODEL_HALFLAMBERT
		diffuse += pow(0.5 * NdotL + 0.5, 2) * INTENSITY[i]; 
		#endif
		#ifdef LIGHTMODEL_PHONG
		diffuse += NdotL * INTENSITY[i];
		#endif
	}

	float specular = In.Specular * vSpecColor.r;
	
#ifdef DEBUG_SHOW_SPECULARMAP
	return float4(tex2D( SpecularMap, In.vTexCoord0 ).r * float3(1,1,1), 1.0);   // specularity
#endif
#ifdef DEBUG_SHOW_NORMALMAP
	return float4(tex2D( NormalMap, In.vTexCoord0 ).rgb, 1.0);     // normals
#endif
#ifdef DEBUG_SHOW_TEXCOORDS
	return float4(In.vTexCoord0.xy, 0.0, 1.0);                     // texture coordinates
#endif
	
#ifdef DEBUG_ONLY_DIFFUSE
	return float4(float3(1,1,1) * diffuse, vColor.a);
#endif
#ifdef DEBUG_ONLY_SPECULAR
	return float4(float3(1,1,1) * specular, vColor.a);
#endif
#ifdef DEBUG_ONLY_COLORMAP
	return vColor;
#endif
	
	diffuse = max(diffuse, SAIL_SHINETHROUGH * vSpecColor.g);
	vColor.rgb = lerp(vColor.rgb, vFlagColor.rgb, vSpecColor.g);
	return float4(vColor.rgb * diffuse + specular, vColor.a); // normal

}

technique Standard
{
	pass p0
	{
		VertexShader = compile vs_2_0 SkinnedAvatarVS();
		PixelShader = compile ps_2_0 SkinnedAvatarPS();
	}
}
