package RepoManager

import (
	"crossform.io/pkg/logger"
	"crossform.io/pkg/repo"
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
				m.log.Debug().Str("config", config.Name).Msg("config update received")
				r, err := m.getRepo(config.Uuid)
				if err != nil {
					m.log.Debug().Str("config", config.Name).Msg("repository not found, creating a new one")
					r = repo.NewRepo(config)
					m.repos[config.Uuid] = r
				} else {
					m.log.Debug().Str("config", config.Name).Msg("repository found, updating config")
					r.UpdateConfig(config)
				}
			case config := <-m.ConfigDeletes:
				m.log.Debug().Str("name", config.Name).Msg("config delete received")
				r, err := m.getRepo(config.Uuid)
				if err != nil {
					m.log.Warn().Str("name", config.Name).Msg("repository not found")
					continue
				}

				err = r.Destroy()
				if err != nil {
					m.log.Error().Err(err).Str("name", config.Name).Msg("repository destroy failed")
				}
				delete(m.repos, config.Uuid)
			}
		}
	}
}

func (m *RepoManager) getRepo(name string) (*repo.Repo, error) {
	m.locker.RLock()
	defer m.locker.RUnlock()
	prev := m.repos[name]
	if prev == nil {
		m.log.Warn().Str("name", name).Msg("repository not found")
		return nil, errors.New("Repository not found: " + name)
	}
	return prev, nil
}

//func (m *RepoManager) Execute(execute *executor.ExecCommand) (*executor.ExecResult, error) {
//	prev, err := m.getRepo(execute.RepositoryName)
//	if err != nil {
//		m.log.Error().Str("name", execute.RepositoryName).Msg("repository not found")
//		return nil, err
//	}
//	return prev.Execute(execute)
//}

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
