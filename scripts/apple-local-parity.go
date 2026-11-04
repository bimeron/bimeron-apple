package main

import (
	"bimeron/release/applemanifest"
	"crypto/ed25519"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	root := os.Args[1]
	data, e := os.ReadFile(filepath.Join(root, "index.json"))
	if e != nil {
		panic(e)
	}
	var vectors []struct {
		File, Arch string
		Accept     bool
	}
	if e = json.Unmarshal(data, &vectors); e != nil {
		panic(e)
	}
	for _, v := range vectors {
		b, e := os.ReadFile(filepath.Join(root, v.File))
		if e != nil {
			panic(e)
		}
		manifest, err := os.ReadFile(filepath.Join(root, v.File+".manifest.json"))
		if err != nil {
			panic(err)
		}
		signature, err := os.ReadFile(filepath.Join(root, v.File+".manifest.sig"))
		if err != nil {
			panic(err)
		}
		public := ed25519.NewKeyFromSeed(make([]byte, 32)).Public().(ed25519.PublicKey)
		verified, err := applemanifest.VerifyManifest(manifest, signature, public, "v0.1.0-beta.1", "e8de4354e2dc5d0364a2fb93119c50971cdf8a5c")
		if err != nil {
			panic(err)
		}

		other := "amd64"
		if v.Arch == other {
			other = "arm64"
		}
		counterpart, err := os.ReadFile(filepath.Join(root, other+"-original.zip"))
		if err != nil {
			panic(err)
		}
		archives := map[string][]byte{v.Arch: b, other: counterpart}
		if err = verified.VerifyArchives(archives); (err == nil) != v.Accept {
			panic(fmt.Sprintf("authenticated %s: %v", v.File, err))
		}
		archives[v.Arch] = append(append([]byte{}, b...), 0)
		if verified.VerifyArchives(archives) == nil {
			panic("accepted tampered archive")
		}

		e = applemanifest.CheckArchive(b, v.Arch, "e8de4354e2dc5d0364a2fb93119c50971cdf8a5c", "0.1.0-beta.1")
		if (e == nil) != v.Accept {
			panic(fmt.Sprintf("%s: %v", v.File, e))
		}
	}
	fmt.Printf("PASS %d Core archive vectors\n", len(vectors))
}
