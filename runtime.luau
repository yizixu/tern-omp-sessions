local windows = tern.runtime.os == "windows"

return {
	windows = windows,
	node = if windows then "node.exe" else "node",
	tern = if windows then "tern.com" else "tern",
	omp = if windows then "omp.exe" else "omp",
}
