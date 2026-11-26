using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace PartyWorld.Net
{
    /// <summary>
    /// 온라인 서버 입장용 Firebase 게스트 로그인 (Godot scripts/auth/firebase_auth.gd 의 sign_in_anonymous + 토큰 갱신).
    /// 서버는 Firebase ID 토큰을 검사하므로, 로그인하지 않은 사람은 처음 한 번 게스트 계정을 만든다.
    /// 갱신 토큰은 이 브라우저에 저장해서 다음에 와도 같은 계정(같은 진행도)으로 들어간다.
    /// 이메일·Google 로그인은 로그인 화면을 옮길 때 이 클래스에 붙인다.
    /// </summary>
    public static class GuestAuth
    {
        /// <summary>
        /// Firebase 웹 API 키 (config/firebase.cfg 와 같은 값). 웹 페이지에 그대로 들어가는 공개 식별자라 비밀이 아니다.
        /// </summary>
        public const string ApiKey = "AIzaSyAP759vW7WUhPLiHcYQItaiz3deWXTB9nA";
        const string AuthBase = "https://identitytoolkit.googleapis.com/v1";
        const string TokenBase = "https://securetoken.googleapis.com/v1";
        const int RefreshMarginSec = 300;

        public static string IdToken { get; private set; } = "";
        public static string Uid { get; private set; } = "";
        public static string LastError { get; private set; } = "";
        static long _expiresAt;

        [Serializable] class SignUpRes { public string idToken; public string refreshToken; public string expiresIn; public string localId; }
        [Serializable] class RefreshRes { public string id_token; public string refresh_token; public string expires_in; public string user_id; }

        static long Now => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        public static bool HasValidToken => IdToken != "" && Now < _expiresAt - RefreshMarginSec;

        /// <summary>쓸 수 있는 ID 토큰을 준비한다 (저장된 계정 갱신, 없으면 게스트 계정 생성). 실패하면 IdToken == ""</summary>
        public static IEnumerator Ensure()
        {
            LastError = "";
            if (HasValidToken) yield break;
            string refresh = PlayerPrefs.GetString("fb_refresh", "");
            if (refresh != "")
            {
                yield return Refresh(refresh);
                if (HasValidToken) yield break;
            }
            yield return Post(AuthBase + "/accounts:signUp?key=" + ApiKey, "application/json", "{\"returnSecureToken\":true}", text =>
            {
                var r = JsonUtility.FromJson<SignUpRes>(text);
                Store(r.idToken, r.refreshToken, r.expiresIn, r.localId);
            });
        }

        static IEnumerator Refresh(string refresh)
        {
            string body = "grant_type=refresh_token&refresh_token=" + UnityWebRequest.EscapeURL(refresh);
            yield return Post(TokenBase + "/token?key=" + ApiKey, "application/x-www-form-urlencoded", body, text =>
            {
                var r = JsonUtility.FromJson<RefreshRes>(text);
                Store(r.id_token, r.refresh_token, r.expires_in, r.user_id);
            });
        }

        static void Store(string id, string refresh, string expiresIn, string uid)
        {
            if (string.IsNullOrEmpty(id)) return;
            IdToken = id;
            Uid = uid ?? "";
            long.TryParse(expiresIn, out long sec);
            _expiresAt = Now + (sec > 0 ? sec : 3600);
            if (!string.IsNullOrEmpty(refresh))
            {
                PlayerPrefs.SetString("fb_refresh", refresh);
                PlayerPrefs.Save();
            }
        }

        static IEnumerator Post(string url, string type, string body, Action<string> onOk)
        {
            using (var req = new UnityWebRequest(url, "POST"))
            {
                req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
                req.downloadHandler = new DownloadHandlerBuffer();
                req.SetRequestHeader("Content-Type", type);
                req.timeout = 15;
                yield return req.SendWebRequest();
                if (req.result == UnityWebRequest.Result.Success)
                {
                    try { onOk(req.downloadHandler.text); }
                    catch (Exception e) { LastError = e.Message; }
                }
                else LastError = req.error + " " + (req.downloadHandler != null ? req.downloadHandler.text : "");
            }
        }

        public static void SignOut()
        {
            IdToken = "";
            Uid = "";
            _expiresAt = 0;
            PlayerPrefs.DeleteKey("fb_refresh");
        }
    }
}
