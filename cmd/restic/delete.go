package main

import (
	"github.com/restic/restic/internal/restic"
	"golang.org/x/sync/errgroup"
)

// DeleteFiles deletes the given fileList of fileType in parallel
// it will print a warning if there is an error, but continue deleting the remaining files
func DeleteFiles(gopts GlobalOptions, repo restic.Repository, fileList restic.IDSet, fileType restic.FileType) {
	_ = deleteFiles(gopts, true, repo, fileList, fileType)
}

// DeleteFilesChecked deletes the given fileList of fileType in parallel
// if an error occurs, it will cancel and return this error
func DeleteFilesChecked(gopts GlobalOptions, repo restic.Repository, fileList restic.IDSet, fileType restic.FileType) error {
	return deleteFiles(gopts, false, repo, fileList, fileType)
}

const numDeleteWorkers = 8

// deleteFiles deletes the given fileList of fileType in parallel
// if ignoreError=true, it will print a warning if there was an error, else it will abort.
func deleteFiles(gopts GlobalOptions, ignoreError bool, repo restic.Repository, fileList restic.IDSet, fileType restic.FileType) error {
	totalCount := len(fileList)
	fileChan := make(chan restic.ID)
	wg, ctx := errgroup.WithContext(gopts.ctx)
	wg.Go(func() error {
		defer close(fileChan)
		for id := range fileList {
			select {
			case fileChan <- id:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		return nil
	})

	bar := newProgressMax(!gopts.JSON && !gopts.Quiet, uint64(totalCount), "files deleted")
	defer bar.Done()
	for i := 0; i < numDeleteWorkers; i++ {
		wg.Go(func() error {
			for id := range fileChan {
				h := restic.Handle{Type: fileType, Name: id.String()}
				err := repo.Backend().Remove(ctx, h)
				if err != nil {
					if !gopts.JSON {
						Warnf("unable to remove %v from the repository\n", h)
					}
					if !ignoreError {
						return err
					}
				}
				if !gopts.JSON && gopts.verbosity > 2 {
					Verbosef("removed %v\n", h)
				}
				bar.Add(1)
			}
			return nil
		})
	}
	err := wg.Wait()
	return err
}
