package RepoManager

import (
	"crossform.io/pkg/executor"
	"crossform.io/pkg/logger"
	"crossform.io/pkg/repo"
	"crypto/md5"
	"encoding/hex"
	"errors"
	"github.com/rs/zerolog"
	"os"
	"sync"
)

type RepoManager struct {
	repos         map[string]*repo.Repo
	locker        sync.RWMutex
	ConfigUpdates chan *repo.Config
	ConfigDeletes chan *repo.Config
	stop          chan bool
	log           zerolog.Logger
	uses          map[string]int
}

func NewRepoManager() *RepoManager {
	if _, err := os.Stat("./repos"); os.IsNotExist(err) {
		err = os.Mkdir("./repos", 0755)
		CheckIfError(err)
	} else {
		err = os.RemoveAll("./repos")
		CheckIfError(err)
		err = os.Mkdir("./repos", 0755)
		CheckIfError(err)
	}
	r := &RepoManager{
		repos:         map[string]*repo.Repo{},
		ConfigUpdates: make(chan *repo.Config, 10000),
		ConfigDeletes: make(chan *repo.Config, 10000),
		log:           logger.GetLogger("RepoManager").With().Logger(),
		uses:          make(map[string]int),
	}
	go r.worker()
	return r
}

func (m *RepoManager) worker() {
	for {
		select {
		case <-m.stop:
			m.log.Debug().Msg("Got stop message")
			return
		default:
			select {
			case config := <-m.ConfigUpdates:
				m.log.Debug().Str("config", config.Url).Msg("config update received")
				r, err := m.getRepoByHash(config.Hash)
				if err != nil {
					m.log.Debug().Str("config", config.Url).Msg("repository not found, creating a new one")
					r = repo.NewRepo(config)
					m.repos[config.Hash] = r
					m.uses[config.Hash] = 1
				} else {
					m.uses[config.Hash] = m.uses[config.Hash] + 1
				}
			case config := <-m.ConfigDeletes:
				m.log.Debug().Str("name", config.Url).Msg("config delete received")
				r, err := m.getRepoByHash(config.Hash)
				if err != nil {
					m.log.Warn().Str("name", config.Url).Msg("repository not found")
					continue
				}
				if m.uses[config.Hash] > 1 {
					m.uses[config.Hash] = m.uses[config.Hash] - 1
					continue
				}
				err = r.Destroy()
				if err != nil {
					m.log.Error().Err(err).Str("name", config.Url).Msg("repository destroy failed")
				}
				delete(m.repos, config.Hash)
				delete(m.uses, config.Hash)
			}
		}
	}
}

func (m *RepoManager) getRepoByHash(hash string) (*repo.Repo, error) {
	m.locker.RLock()
	defer m.locker.RUnlock()
	prev := m.repos[hash]
	if prev == nil {
		m.log.Warn().Str("hash", hash).Msg("repository not found")
		return nil, errors.New("Repository not found: " + hash)
	}
	return prev, nil
}

func (m *RepoManager) getRepo(url string, revision string) (*repo.Repo, error) {
	h := md5.Sum([]byte(url + revision))
	hash := hex.EncodeToString(h[:])
	m.locker.RLock()
	defer m.locker.RUnlock()
	prev := m.repos[hash]
	if prev == nil {
		m.log.Warn().Str("hash", hash).Msg("repository not found")
		return nil, errors.New("Repository not found: " + hash)
	}
	return prev, nil
}

func (m *RepoManager) Execute(execute *executor.ExecCommand) (*executor.ExecResult, error) {
	prev, err := m.getRepo(execute.RepositoryUrl, execute.RepositoryRevision)
	if err != nil {
		m.log.Error().Str("url", execute.RepositoryUrl).Str("revision", execute.RepositoryRevision).Msg("repository not found")
		return nil, err
	}
	return prev.Execute(execute)
}

func (m *RepoManager) Destroy() {
	m.log.Debug().Msg("destroy")
	m.stop <- true
	for name, v := range m.repos {
		err := v.Destroy()
		if err != nil {
			m.log.Error().Err(err).Str("repositoryName", name).Msg("Destroy repository failed")
		}
	}
}
