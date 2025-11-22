//------------------------------------------------------------------------------
//  Shader code for texcube-sapp sample.
//
//  NOTE: This source file also uses the '#pragma sokol' form of the
//  custom tags.
//------------------------------------------------------------------------------
@header package game
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    mat4 mvp;
};

in vec4 pos;
in vec4 color0;
in vec2 texcoord0;

out vec4 color;
out vec2 uv;

void main() {
    gl_Position = mvp * pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv) * color;
}
@end

@program texcube vs fs

@vs vs_skinned
layout(binding=0) uniform vs_params_skinned {
    mat4 mvp;
    mat4 joint_matrices[64];
};

in vec4 pos;
in vec4 color0;
in vec2 texcoord0;
in vec4 joints;
in vec4 weights;

out vec4 color;
out vec2 uv;

void main() {
    mat4 skin_mat = mat4(0.0);
    for(int i=0; i<4; i++) {
        int joint_idx = int(joints[i]);
        skin_mat += joint_matrices[joint_idx] * weights[i];
    }
    
    if (dot(weights, vec4(1.0)) < 0.01) {
        skin_mat = mat4(1.0);
    }

    gl_Position = mvp * skin_mat * pos;
    color = color0;
    uv = texcoord0;
}
@end

@fs fs_skinned
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv) * color;
}
@end

@program skinned vs_skinned fs_skinned
