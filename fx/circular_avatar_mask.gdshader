shader_type canvas_item;
render_mode unshaded;

// Godot 传入 fragment 的 COLOR 已经包含纹理颜色与节点/父层调制。
// 这里只裁掉圆外像素，圆内不重新采样、不改 RGB，避免二次乘色发黑，
// 同时保留 READY、ESC 菜单等父层淡入透明度。
void fragment() {
	vec2 point = UV - vec2(0.5);
	if (dot(point, point) > 0.25) {
		discard;
	}
}
