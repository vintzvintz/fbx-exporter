package fbx

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/hex"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/vintzvintz/fbx-exporter/internal/log"
)

type sessionInfo struct {
	sessionToken string
	challenge    string
}

type retryConfig struct {
	minDelay      time.Duration
	maxDelay      time.Duration
	currentDelay  time.Duration
	failureCount  int
	lastFailure   time.Time
}

func newRetryConfig() *retryConfig {
	minDelay := 5 * time.Second
	if env := os.Getenv("FBX_RETRY_MIN_DELAY"); env != "" {
		if d, err := time.ParseDuration(env); err == nil {
			minDelay = d
		}
	}

	maxDelay := 1 * time.Minute
	if env := os.Getenv("FBX_RETRY_MAX_DELAY"); env != "" {
		if d, err := time.ParseDuration(env); err == nil {
			maxDelay = d
		}
	}

	return &retryConfig{
		minDelay:     minDelay,
		maxDelay:     maxDelay,
		currentDelay: minDelay,
	}
}

// FreeboxSession represents all the variables used in a session
type FreeboxSession struct {
	client             FreeboxHttpClient
	getSessionTokenURL string
	getChallengeURL    string

	appToken string

	sessionTokenLastUpdate time.Time
	sessionTokenLock       sync.Mutex
	sessionInfo            *sessionInfo
	oldSessionInfo         *sessionInfo // avoid deleting the sessionInfo too quickly

	retryConfig *retryConfig
}

func NewFreeboxSession(appToken string, client FreeboxHttpClient, apiVersion *FreeboxAPIVersion, queryVersion int) (FreeboxHttpClient, error) {
	getChallengeURL, err := apiVersion.GetURL(queryVersion, "login/")
	if err != nil {
		return nil, err
	}

	getSessionTokenURL, err := apiVersion.GetURL(queryVersion, "login/session/")
	if err != nil {
		return nil, err
	}

	result := &FreeboxSession{
		client:             client,
		getSessionTokenURL: getSessionTokenURL,
		getChallengeURL:    getChallengeURL,

		appToken: appToken,

		retryConfig: newRetryConfig(),
	}
	if err := result.refresh(); err != nil {
		return nil, err
	}
	return result, nil
}

func (f *FreeboxSession) Get(url string, out interface{}, callbacks ...FreeboxHttpClientCallback) error {
	action := func() error {
		return f.client.Get(url, out, f.addHeader)
	}
	return f.do(action)
}

func (f *FreeboxSession) Post(url string, in interface{}, out interface{}, callbacks ...FreeboxHttpClientCallback) error {
	action := func() error {
		return f.client.Post(url, in, out, f.addHeader)
	}
	return f.do(action)
}

func (f *FreeboxSession) do(action func() error) error {
	if err := action(); err != nil {
		switch err {
		case errAuthRequired, errInvalidToken:
			// Apply exponential backoff if there were recent failures
			if f.shouldWaitBeforeRetry() {
				log.Warning.Printf("Login failure backoff: waiting %v before retry (failure count: %d)",
					f.retryConfig.currentDelay, f.retryConfig.failureCount)
				time.Sleep(f.retryConfig.currentDelay)
			}

			err := f.refresh()
			if err != nil {
				f.recordFailure()
				return err
			}

			// Reset retry state on successful refresh
			f.resetRetryState()
			return action()
		default:
			return err
		}
	}

	return nil
}

func (f *FreeboxSession) shouldWaitBeforeRetry() bool {
	if f.retryConfig.failureCount == 0 {
		return false
	}

	// If the last failure was recent, apply backoff
	return time.Since(f.retryConfig.lastFailure) < f.retryConfig.currentDelay*2
}

func (f *FreeboxSession) recordFailure() {
	f.retryConfig.failureCount++
	f.retryConfig.lastFailure = time.Now()

	// Exponential backoff: double the delay up to max
	f.retryConfig.currentDelay *= 2
	if f.retryConfig.currentDelay > f.retryConfig.maxDelay {
		f.retryConfig.currentDelay = f.retryConfig.maxDelay
	}

	log.Warning.Printf("Login failure recorded (count: %d, next delay: %v)",
		f.retryConfig.failureCount, f.retryConfig.currentDelay)
}

func (f *FreeboxSession) resetRetryState() {
	if f.retryConfig.failureCount > 0 {
		log.Info.Printf("Login successful, resetting retry state (was %d failures)", f.retryConfig.failureCount)
		f.retryConfig.failureCount = 0
		f.retryConfig.currentDelay = f.retryConfig.minDelay
	}
}

func (f *FreeboxSession) addHeader(req *http.Request) {
	if f != nil && f.sessionInfo != nil {
		req.Header.Set("X-Fbx-App-Auth", f.sessionInfo.sessionToken)
	}
}

func (f *FreeboxSession) refresh() error {
	f.sessionTokenLock.Lock()
	defer f.sessionTokenLock.Unlock()

	if sinceLastUpdate := time.Since(f.sessionTokenLastUpdate); sinceLastUpdate < 5*time.Second {
		log.Debug.Printf("Updated %v ago. Skipping", sinceLastUpdate)
		return nil
	}

	challenge, err := f.getChallenge()
	if err != nil {
		return err
	}
	sessionToken, err := f.getSessionToken(challenge)
	if err != nil {
		return err
	}
	f.sessionTokenLastUpdate = time.Now()
	f.oldSessionInfo = f.sessionInfo
	f.sessionInfo = &sessionInfo{
		challenge:    challenge,
		sessionToken: sessionToken,
	}
	return nil
}

func (f *FreeboxSession) getChallenge() (string, error) {
	log.Debug.Println("GET challenge:", f.getChallengeURL)
	resStruct := struct {
		Challenge string `json:"challenge"`
	}{}

	if err := f.client.Get(f.getChallengeURL, &resStruct); err != nil {
		return "", err
	}

	log.Debug.Println("Challenge:", resStruct.Challenge)
	return resStruct.Challenge, nil
}

func (f *FreeboxSession) getSessionToken(challenge string) (string, error) {
	log.Debug.Println("GET SessionToken:", f.getSessionTokenURL)
	freeboxAuthorize := getFreeboxAuthorize()

	hash := hmac.New(sha1.New, []byte(f.appToken))
	hash.Write([]byte(challenge))
	password := hex.EncodeToString(hash.Sum(nil))

	reqStruct := struct {
		AppID    string `json:"app_id"`
		Password string `json:"password"`
	}{
		AppID:    freeboxAuthorize.AppID,
		Password: password,
	}
	resStruct := struct {
		SessionToken string `json:"session_token"`
	}{}

	if err := f.client.Post(f.getSessionTokenURL, &reqStruct, &resStruct); err != nil {
		return "", err
	}

	log.Debug.Println("SessionToken:", resStruct.SessionToken)
	return resStruct.SessionToken, nil
}
