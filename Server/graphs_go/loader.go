package graphs_go

import (
	"encoding/json"
	"fmt"
	"github.com/mohamedthameursassi/GoServer/models"
	"github.com/mohamedthameursassi/GoServer/utils"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"
)

func LoadGraphFromFile(path string) (*Graph, error) {
	fmt.Printf("📂 Loading graph from: %s\n", path)

	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("could not open graph file: %w", err)
	}
	defer file.Close()

	bytes, err := ioutil.ReadAll(file)
	if err != nil {
		return nil, fmt.Errorf("could not read graph file: %w", err)
	}

	var metaWrapper struct {
		Metadata struct {
			ModeInfo struct {
				Mode string `json:"mode"`
			} `json:"mode_info"`
		} `json:"metadata"`
	}
	if err := json.Unmarshal(bytes, &metaWrapper); err != nil {
		return nil, fmt.Errorf("could not parse graph metadata: %w", err)
	}

	modes := strings.Split(metaWrapper.Metadata.ModeInfo.Mode, "_")
	var parsedModes []models.TransportMode
	for _, m := range modes {
		parsedModes = append(parsedModes, utils.ParseTransportMode(m))
	}

	graph, err := LoadGraphFromJSON(bytes)
	if err != nil {
		return nil, err
	}

	graph.Modes = parsedModes
	return graph, nil
}

func LoadGraphsFromDirectory(folder string) (map[string]*Graph, error) {
	graphs := make(map[string]*Graph)

	err := filepath.Walk(folder, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && strings.HasSuffix(info.Name(), ".json") {
			graph, err := LoadGraphFromFile(path)
			if err != nil {
				return fmt.Errorf("error loading graph from %s: %w", path, err)
			}
			key := strings.TrimSuffix(info.Name(), ".json")
			graphs[key] = graph
		}
		return nil
	})

	if err != nil {
		return nil, err
	}
	return graphs, nil
}
