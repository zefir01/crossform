package repo

import (
	"crossform.io/pkg/executor"
	"crossform.io/pkg/logger"
	"errors"
	"fmt"
	"github.com/go-git/go-git/v5"
	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/protocol/packp/capability"
	"github.com/go-git/go-git/v5/plumbing/transport"
	"github.com/go-git/go-git/v5/plumbing/transport/http"
	"github.com/go-git/go-git/v5/plumbing/transport/ssh"
	"github.com/rs/zerolog"
	ssh2 "golang.org/x/crypto/ssh"
	"os"
	"sync"
	"time"
)

type RevisionType int8

const (
	Commit RevisionType = iota
	Branch RevisionType = iota
	Tag    RevisionType = iota
)

func (e RevisionType) String() string {
	switch e {
	case Commit:
		return "Commit"
	case Branch:
		return "Branch"
	case Tag:
		return "Tag"
	default:
		return fmt.Sprintf("%d", int(e))
	}
}

type Repo struct {
	config       *Config
	repo         *git.Repository
	revisionType RevisionType
	Locker       sync.RWMutex
	stop         chan bool
	Status       *Status
	log          zerolog.Logger
}

func NewRepo(config *Config) *Repo {
	repo := Repo{
		config: config,
		Status: NewStatus(),
		Locker: sync.RWMutex{},
		stop:   make(chan bool),
		log:    logger.GetLogger("repository").With().Str("url", config.Url).Logger(),
	}
	go repo.worker()
	return &repo
}

func (repo *Repo) init() error {
	repo.log.Debug().Msg("init")
	var err error
	repo.repo, err = repo.initRepo()
	if err != nil {
		return err
	}
	repo.revisionType, err = repo.detectRevisionType()
	repo.log.Debug().Str("revisionType", repo.revisionType.String()).Msg("revision type detected")
	if err != nil {
		return err
	}
	err = repo.checkout()
	if err != nil {
		return err
	}
	repo.log.Debug().Msg("init success")
	return nil
}

func (repo *Repo) getAuth() (transport.AuthMethod, error) {
	data, err := repo.config.GetSecretData()
	if err != nil {
		return nil, err
	}
	var auth transport.AuthMethod
	if data.PrivateKey != "" {
		a, err := ssh.NewPublicKeys("git", []byte(data.PrivateKey), "")
		if err != nil {
			repo.log.Error().Err(err).Msg("Generate public keys failed")
			return nil, err
		}
		a.HostKeyCallback = ssh2.InsecureIgnoreHostKey()
		if err != nil {
			repo.log.Error().Err(err).Msg("Generate public keys failed:")
			return nil, err
		}
		auth = a
	} else if data.Username != "" {
		auth = &http.BasicAuth{
			Username: data.Username,
			Password: data.Password,
		}
	}
	repo.log.Debug().Str("auth", auth.Name()).Msg("auth detected")
	return auth, nil
}

func (repo *Repo) initRepo() (*git.Repository, error) {
	// Clone the given repository to the given Path
	repo.log.Info().Str("url", repo.config.Url).Msg("git clone")
	transport.UnsupportedCapabilities = []capability.Capability{
		capability.ThinPack,
	}
	auth, err := repo.getAuth()
	if err != nil {
		return nil, err
	}

	r, err := git.PlainClone(repo.config.Path, false, &git.CloneOptions{
		Auth:     auth,
		URL:      repo.config.Url,
		Progress: os.Stdout,
	})
	if err != nil {
		return nil, err
	}
	repo.log.Debug().Str("url", repo.config.Url).Msg("git clone success")

	return r, nil
}

func (repo *Repo) detectRevisionType() (RevisionType, error) {
	repo.log.Debug().Msg("detecting revision type")
	if plumbing.IsHash(repo.config.Revision) {
		_, err := repo.repo.CommitObject(plumbing.NewHash(repo.config.Revision))
		if err != nil {
			return 0, err
		}
		return Commit, nil
	}

	_, err := repo.repo.Tag(repo.config.Revision)
	if err == nil {
		return Tag, nil
	}

	_, err = repo.repo.Branch(repo.config.Revision)
	if err == nil {
		return Branch, nil
	}

	return 0, errors.New("undetected Revision type")
}

func (repo *Repo) getCommitSha() string {
	head, err := repo.repo.Head()
	if err != nil {
		repo.log.Error().Err(err).Msg("Get HEAD sha failed")
	}
	return head.Hash().String()
}

func (repo *Repo) checkout() error {
	repo.log.Debug().Str("revision", repo.config.Revision).Msg("checkout")
	w, _ := repo.repo.Worktree()
	switch repo.revisionType {
	case Branch:
		err := w.Checkout(&git.CheckoutOptions{
			Branch: plumbing.NewBranchReferenceName(repo.config.Revision),
		})
		if err == nil {
			repo.log.Debug().Str("revision", repo.config.Revision).Msg("checkout Branch success")
		}
		return err
	case Commit:
		hash := plumbing.NewHash(repo.config.Revision)
		_, err := repo.repo.CommitObject(hash)
		if err != nil {
			return err
		}
		err = w.Checkout(&git.CheckoutOptions{
			Hash: hash,
		})
		if err == nil {
			repo.log.Debug().Str("revision", repo.config.Revision).Msg("checkout Commit success")
		}
		return err
	case Tag:
		t, err := repo.repo.Tag(repo.config.Revision)
		if err != nil {
			return err
		}
		err = w.Checkout(&git.CheckoutOptions{
			Hash: t.Hash(),
		})
		if err == nil {
			repo.log.Debug().Str("revision", repo.config.Revision).Msg("checkout Tag success")
		}
		return err
	default:
		return nil
	}
}

func (repo *Repo) checkUpdates() (bool, error) {
	repo.log.Debug().Msg("Checking for updates")
	switch repo.revisionType {
	case Commit:
		return false, nil
	case Branch:
		auth, err := repo.getAuth()
		if err != nil {
			return false, err
		}
		err = repo.repo.Fetch(&git.FetchOptions{
			RemoteName: "origin",
			Auth:       auth,
		})
		if err != nil {
			if fmt.Sprint(err) != "already up-to-date" {
				return false, err
			}
			repo.log.Debug().Msg("already up-to-date")
		}
		repo.log.Debug().Msg("fetch success")

		r, _ := repo.repo.Head()
		if r.Name().Short() != plumbing.NewBranchReferenceName(repo.config.Revision).Short() {
			return false, errors.New("wrong branch")
		}

		rem, err := repo.repo.Reference(plumbing.NewRemoteReferenceName("origin", repo.config.Revision), true)
		if err != nil {
			return false, err
		}
		remoteCommit, err := repo.repo.CommitObject(rem.Hash())
		if err != nil {
			return false, err
		}

		repo.log.Debug().
			Str("remoteCommit", remoteCommit.Hash.String()).
			Str("localCommit", r.Hash().String()).
			Bool("needUpdate", r.Hash().String() != remoteCommit.Hash.String()).
			Msg("get commit hashes success")
		return r.Hash().String() != remoteCommit.Hash.String(), nil
	case Tag:
		err := repo.repo.Fetch(&git.FetchOptions{RemoteName: "origin"})
		if err != nil {
			if fmt.Sprint(err) != "already up-to-date" {
				return false, err
			}
			repo.log.Debug().Msg("already up-to-date")
		}
		repo.log.Debug().Msg("fetch success")

		remote, _ := repo.repo.Remote("origin")
		refs, err := remote.List(&git.ListOptions{
			PeelingOption: git.AppendPeeled,
		})
		if err != nil {
			return false, errors.New("unable to get remote tags")
		}
		var remoteRef *plumbing.Reference = nil
		for _, ref := range refs {
			if ref.Name().IsTag() && ref.Name().Short() == repo.config.Revision {
				remoteRef = ref
			}
		}
		if remoteRef == nil {
			return false, errors.New("remote tag not found")
		}
		if err != nil {
			return false, err
		}
		repo.log.Debug().
			Str("remoteCommit", remoteRef.Hash().String()).
			Str("localCommit", repo.getCommitSha()).
			Bool("needUpdate", remoteRef.Hash().String() != repo.getCommitSha()).
			Msg("get commit hashes success")
		return remoteRef.Hash().String() != repo.getCommitSha(), nil
	default:
		return false, errors.New("incorrect Revision type")
	}
}

func (repo *Repo) update() error {
	repo.log.Info().Msg("Updating")
	//repo.Locker.Lock()
	//repo.log.Debug().Msg("locked")
	//unlock := func() {
	//	repo.Locker.Unlock()
	//	repo.log.Debug().Msg("unlocked")
	//}
	//defer unlock()
	switch repo.revisionType {
	case Commit:
		err := repo.checkout()
		if err != nil {
			return err
		}
		return err
	case Tag:
		err := repo.checkout()
		if err != nil {
			return err
		}
		return err
	case Branch:
		auth, err := repo.getAuth()
		if err != nil {
			return err
		}
		w, _ := repo.repo.Worktree()
		err = w.Pull(&git.PullOptions{
			RemoteName: "origin",
			Auth:       auth,
		})
		if err != nil {
			return err
		}
		return err
	default:
		return errors.New("undetected Revision type")
	}
}

func (repo *Repo) worker() {
	log := repo.log.With().Str("system", "repository worker").Logger()
	log.Debug().Msg("starting")
	for {
		select {
		case <-repo.stop:
			log.Debug().Msg("Got stop message")
			return
		default:
			repo.work()
			time.Sleep(repo.config.UpdatePeriod)
		}
	}
}
func (repo *Repo) work() {
	log := repo.log.With().Str("system", "repository worker").Logger()
	log.Debug().Msg("do work")

	unlock := func() {
		repo.Locker.Unlock()
		repo.log.Debug().Msg("unlocked")
	}
	repo.Locker.Lock()
	repo.log.Debug().Msg("locked")
	defer unlock()

	log.Debug().Object("status", repo.Status).Msg("got status")
	if !repo.Status.IsInitialized {
		err := repo.init()
		if err != nil {
			log.Error().Err(err).Msg("Initialization failed")
			repo.Status.Message = err.Error()
			err := repo.Destroy()
			if err != nil {
				repo.log.Error().Err(err).Msg("Destroy failed")
			}
			return
		}
		repo.Status.IsInitialized = true
		repo.Status.Message = "Repository initialization success"
		repo.Status.IsUpdateSuccess = true
		repo.Status.CommitSha = repo.getCommitSha()
		repo.Status.Revision = repo.config.Revision
		return
	}

	res, err := repo.checkUpdates()
	if err != nil {
		repo.Status.IsUpdateSuccess = false
		repo.Status.Message = err.Error()
		log.Error().Err(err).Msg("check for updates failed")
	}
	repo.log.Debug().Err(err).Msg("check for updates success")

	if res {
		err := repo.update()
		if err != nil {
			repo.Status.IsUpdateSuccess = false
			repo.Status.Message = err.Error()
			log.Error().Err(err).Msg("update failed")
		} else {
			repo.Status.IsUpdateSuccess = true
			repo.Status.Message = "Update success"
			repo.Status.CommitSha = repo.getCommitSha()
			log.Info().Str("revision", repo.Status.Revision).
				Str("commitSha", repo.Status.CommitSha).
				Msg("update success")
		}
	} else {
		repo.Status.IsUpdateSuccess = true
		repo.Status.Message = "No updates"
		repo.Status.CommitSha = repo.getCommitSha()
		log.Debug().Err(err).Msg("no updates")
	}
}

func (repo *Repo) Destroy() error {
	repo.log.Info().Msg("destroy repository")
	repo.Locker.Lock()
	repo.log.Debug().Msg("locked")
	unlock := func() {
		repo.Locker.Unlock()
		repo.log.Debug().Msg("unlocked")
	}
	defer unlock()
	repo.stop <- true
	repo.Status = NewStatus()
	err := os.RemoveAll(repo.config.Path)
	repo.log.Debug().Msg("destroyed")
	return err
}

func (repo *Repo) Execute(task *executor.ExecCommand) (*executor.ExecResult, error) {
	repo.log.Debug().Msg("execute")
	unlock := func() {
		repo.Locker.RUnlock()
		repo.log.Debug().Msg("read unlocked")
	}
	repo.Locker.RLock()
	repo.log.Debug().Msg("read locked")
	defer unlock()
	if !repo.Status.IsInitialized {
		err := errors.New("repository not initialized")
		repo.log.Warn().Err(err).Msg("execution failed")
		return nil, err
	}

	res, err := executor.Execute(repo.config.Path, task)
	if err != nil {
		repo.log.Error().Err(err).Msg("Execution error")
		return nil, err
	}
	return res, err
}
