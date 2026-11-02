import Foundation

public enum SpeechCue: String, Codable, CaseIterable {
    case greeting, wipeRequest, wiping, clean, caughtEating, lastBite, guarding, chasing, disappointed
    case snatched, bonked, startled, caughtBowl, kicked, furious
    case fell, welcomeBack, lateNight, morning, petted, breakTime, hungry, aiWorking, aiDone, fed
    case refilled, hanging, curious, climbed
    public var title: String {
        switch self {
        case .greeting: return "打招呼"
        case .wipeRequest: return "想让你擦脸"
        case .wiping: return "擦脸过程中"
        case .clean: return "擦干净后"
        case .caughtEating: return "偷吃被抓包"
        case .lastBite: return "还想再吃一口"
        case .guarding: return "拿回饭盆"
        case .chasing: return "追着饭盆跑"
        case .disappointed: return "没追上，委屈了"
        case .snatched: return "抢回饭盆"
        case .bonked: return "被饭盆砸到头"
        case .startled: return "被饭盆吓一跳"
        case .caughtBowl: return "接住飞来的饭盆"
        case .kicked: return "不小心踢飞饭盆"
        case .furious: return "连续被抢，生气了"
        case .fell: return "从窗口上掉下来"
        case .welcomeBack: return "你回来了"
        case .lateNight: return "提醒你早点睡"
        case .morning: return "早上问候"
        case .petted: return "被摸头"
        case .breakTime: return "提醒休息"
        case .hungry: return "饭票快用完了"
        case .aiWorking: return "陪你等 AI"
        case .aiDone: return "AI 干完活了"
        case .fed: return "被投喂"
        case .refilled: return "额度重置，米满了"
        case .hanging: return "挂在窗口边上"
        case .curious: return "走过去看你的窗口"
        case .climbed: return "爬上了窗口"
        }
    }
}

public enum SpeechStyle: String, Codable, CaseIterable {
    case soft, playful, tsundere, concise, custom
    public var title: String {
        switch self {
        case .soft: return "软萌"
        case .playful: return "俏皮"
        case .tsundere: return "嘴硬"
        case .concise: return "简洁"
        case .custom: return "自定义"
        }
    }
    public func lines(for cue: SpeechCue) -> [String] {
        let lines: [[String]]
        switch self {
        case .soft, .custom:
            lines = [["你来啦，好开心", "嗨，陪我一会儿嘛"], ["帮我擦擦脸嘛", "脸脏脏的，拜托你啦"], ["轻轻擦一下", "嗯，这边也擦擦"], ["干净啦，谢谢你", "又是干净的小鱼啦"], ["才没有偷吃…", "被你发现啦…"], ["再吃最后一口", "这一口吃完就好啦"], ["我的饭盆！", "抱紧我的白饭"], ["把饭盆还给我嘛", "等等我的白饭呀"], ["没追上，有点委屈", "饭盆也想我了吧"],
                     ["抓到啦，是我的！", "嘿，抢回来啦"], ["哎哟，好痛…", "不许拿饭盆砸我啦"], ["吓我一跳！", "差点被砸到…"],
                     ["接住啦！", "稳稳接住我的饭盆"], ["啊，踢飞了…", "饭盆别跑呀"], ["又抢！我生气了！", "这次一定要追回来"],
                     ["哎呀，掉下来了", "窗户跑掉了…"], ["你回来啦！", "我刚刚睡着了…"], ["已经很晚啦，早点睡", "眼睛要休息了哦"], ["早上好呀！", "新的一天，一起加油"],
                     ["嘿嘿，好舒服", "再摸一下嘛"], ["休息一下吧，喝口水", "站起来伸个懒腰嘛"], ["饭票快用完了…", "今天的白饭不多了"],
                     ["AI 在干活，我陪你等", "一起等它忙完吧"], ["好像忙完啦，去看看", "AI 干完活了哦"], ["嚼嚼，好吃！", "谢谢投喂～"],
                     ["哇，饭票回来啦！", "米满满的，好开心"], ["抓、抓住了…", "要掉下去啦！"],
                     ["你在忙什么呀？", "让我看看这个窗口"], ["爬上来啦！", "这里看得好远"]]
        case .playful:
            lines = [["小鱼上线，啵！", "今日份陪伴已送达"], ["灰脸小鱼申请洗脸", "需要一位擦脸大师"], ["擦擦擦，焕然一鱼", "鱼脸清洁进行中"], ["清洁度满格！", "本鱼又闪亮登场啦"], ["白饭质检，被抓现行", "这是试吃，试吃！"], ["最后亿口！", "饭盆说它还想被吃"], ["饭盆回收成功！", "白饭已重新归队"], ["站住！我的碳水！", "饭盆逃跑啦！"], ["追饭失败，申请安慰", "我的白饭离家出走了"],
                     ["闪电回收！", "饭盆：被鱼夺回"], ["当！头顶命中", "鱼头不是篮筐！"], ["吓得鳞片都竖起来了", "险些中招！"],
                     ["好球！接住了", "单手接饭盆，帅吧"], ["一脚射门…射歪了", "饭盆二次起飞！"], ["又被抢！全速开冲！", "碳水保卫战升级！"],
                     ["窗台塌方！", "高空坠鱼，请注意"], ["主人回归，开机！", "睡醒了，满血复活"], ["夜猫子警报！", "熬夜会变熊猫鱼哦"], ["早安！今日份元气", "太阳晒到鱼尾巴啦"],
                     ["摸头杀，暴击！", "幸福值 +100"], ["休息时间到，立正！", "补水补水，咕嘟咕嘟"], ["碳水告急！", "饭票余额不足警告"],
                     ["AI 搬砖中，围观", "我来给 AI 加油"], ["AI 交作业啦！", "叮！任务完成"], ["咔嚓咔嚓，美味", "投喂成功，好饱"],
                     ["满血复活！碳水到账", "叮！白饭已补货"], ["单杠小鱼上线！", "手、手要酸了"],
                     ["小鱼巡逻中～", "这个窗口有好吃的吗"], ["登顶成功！", "攀岩小鱼，帅吧"]]
        case .tsundere:
            lines = [["才不是在等你呢", "哼，终于想起我啦"], ["才不是要你帮忙呢", "这点灰…你帮我擦嘛"], ["轻一点啦", "那边也…顺手擦一下"], ["勉强谢谢你啦", "哼，擦得还不错"], ["看什么，我没偷吃！", "我只是帮你尝尝"], ["就一口，不许笑", "这口本来就是我的"], ["不许再抢我的饭盆", "哼，总算还回来了"], ["站住，把饭盆还我！", "我的饭，你不许拿！"], ["我才没有想哭", "哼，等你自己还回来"],
                     ["哼，早说了是我的", "手慢了吧"], ["好痛！你故意的吧", "哼，砸我也不还你"], ["才、才没被吓到", "你小心一点啦"],
                     ["哼，接住很简单", "本来就是我的饭盆"], ["刚才那下不算！", "我只是…脚滑了"], ["再抢我真生气了！", "哼，这次不原谅你"],
                     ["才不是没站稳！", "哼，窗户太滑了"], ["哼，终于回来了", "我才没在等你"], ["还不睡？随便你啦", "熬夜我可不管你"], ["早…早上好啦", "哼，今天也来了"],
                     ["才、才不舒服呢", "就允许你摸一下"], ["该休息了，听到没", "我才不是担心你"], ["饭票没多少了…哼", "才没有饿呢"],
                     ["我才不是在陪你等", "AI 还没好吗，真慢"], ["好了，快去看", "哼，总算弄完了"], ["还行吧…再来点", "勉强好吃啦"],
                     ["哼，才没有很开心", "这、这么多米给我的？"], ["我才没有害怕！", "快、快拉我上去啦"],
                     ["我只是路过看看", "才不是好奇呢"], ["哼，这点高度不算什么", "爬上来了，不用夸我"]]
        case .concise:
            lines = [["你好", "我在这里"], ["帮我擦擦脸", "脸上有灰"], ["正在擦脸", "还剩一点"], ["擦干净了，谢谢", "干净了"], ["被发现了", "正在吃饭"], ["最后一口", "快吃完了"], ["饭盆回来了", "收好饭盆"], ["还我饭盆", "等等我"], ["没追上", "休息一下"],
                     ["抢回来了", "拿到了"], ["好痛", "砸到头了"], ["吓一跳", "差点砸到"], ["接住了", "拿回饭盆"], ["踢飞了", "糟糕"], ["生气了", "还我饭盆"],
                     ["掉下来了", "没站稳"], ["欢迎回来", "你回来了"], ["很晚了", "早点睡"], ["早上好", "早安"], ["好舒服", "嘿嘿"], ["休息一下", "喝口水"],
                     ["额度不多了", "饭票快没了"], ["等 AI 中", "陪你等"], ["AI 好了", "任务完成"], ["好吃", "谢谢"],
                     ["额度重置了", "米满了"], ["抓住了", "快掉了"],
                     ["看看窗口", "路过"], ["爬上来了", "到顶了"]]
        }
        return lines[SpeechCue.allCases.firstIndex(of: cue)!]
    }
}

public enum BubbleText {
    public static let limit = 28
    public static func clean(_ text: String) -> String {
        String(text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").prefix(limit))
    }
}

extension Preferences {
    public func speech(for cue: SpeechCue, variant: Int = 0) -> String {
        guard speechEnabled else { return "" }
        if speechStyle == .custom, let text = customSpeech[cue.rawValue] {
            let clean = BubbleText.clean(text)
            if !clean.isEmpty { return clean }
        }
        let candidates = speechStyle.lines(for: cue)
        return candidates[(variant % candidates.count + candidates.count) % candidates.count]
    }
}
