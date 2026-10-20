# ONNX Runtime (used by the on-device ML categorizer).
# Its native library looks up these Java classes by their real names
# (e.g. ai.onnxruntime.TensorInfo). Release builds shrink and rename
# classes with R8, so without these rules the lookup returns null and the
# app aborts the first time the model runs ("java_class == null").
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
