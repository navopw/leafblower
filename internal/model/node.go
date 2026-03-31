package model

import (
	"sync"
	"time"
)

// Node represents a file or directory in the scan tree.
type Node struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Path        string  `json:"path"`
	ParentID    string  `json:"parentId,omitempty"`
	SizeBytes   int64   `json:"sizeBytes"`
	IsDir       bool    `json:"isDir"`
	ChildCount  int     `json:"childCount"`
	HasChildren bool    `json:"hasChildren"`
	Children    []*Node `json:"children,omitempty"`
}

// ScanStatus represents the lifecycle state of a scan job.
type ScanStatus string

const (
	StatusQueued    ScanStatus = "queued"
	StatusRunning   ScanStatus = "running"
	StatusComplete  ScanStatus = "complete"
	StatusFailed    ScanStatus = "failed"
	StatusCancelled ScanStatus = "cancelled"
)

// ScanWarning records a path that could not be scanned.
type ScanWarning struct {
	Path string `json:"path"`
	Code string `json:"code"`
}

// ScanJob holds the full state of a scan.
type ScanJob struct {
	Mu                 sync.Mutex    `json:"-"`
	ID                 string        `json:"scanId"`
	RootPath           string        `json:"rootPath"`
	IncludeHidden      bool          `json:"includeHidden"`
	Status             ScanStatus    `json:"status"`
	DirectoriesVisited int64         `json:"directoriesVisited"`
	FilesVisited       int64         `json:"filesVisited"`
	BytesSeen          int64         `json:"bytesSeen"`
	Warnings           []ScanWarning `json:"warnings"`
	RootNode           *Node         `json:"-"`
	NodeIndex          map[string]*Node `json:"-"`
	CreatedAt          time.Time     `json:"createdAt"`
}

// ProgressEvent is sent over SSE during scanning.
type ProgressEvent struct {
	Type               string `json:"type"`
	ScanID             string `json:"scanId"`
	Phase              string `json:"phase,omitempty"`
	CurrentPath        string `json:"currentPath,omitempty"`
	DirectoriesVisited int64  `json:"directoriesVisited,omitempty"`
	FilesVisited       int64  `json:"filesVisited,omitempty"`
	BytesSeen          int64  `json:"bytesSeen,omitempty"`
	DirsQueued         int64  `json:"dirsQueued,omitempty"`
	DirsDone           int64  `json:"dirsDone,omitempty"`
	WarningCount       int    `json:"warnings,omitempty"`
	RootNodeID         string `json:"rootNodeId,omitempty"`
}

// DeleteRequest is the payload for deletion.
type DeleteRequest struct {
	ScanID  string   `json:"scanId"`
	NodeIDs []string `json:"nodeIds"`
}

// DeleteResult holds per-target outcome.
type DeleteResult struct {
	NodeID string `json:"nodeId"`
	Path   string `json:"path"`
	Error  string `json:"error,omitempty"`
}

// DeleteResponse is the API response for deletion.
type DeleteResponse struct {
	Deleted []DeleteResult `json:"deleted"`
	Failed  []DeleteResult `json:"failed"`
}
